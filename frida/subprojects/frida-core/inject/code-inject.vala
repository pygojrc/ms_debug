namespace Frida.Inject {
	private static Application application;

	private static int target_pid = -1;
	private static string? data;
	private static string? command;
	private static bool commercial_wrapper;
	private static bool output_version;

	const OptionEntry[] code_options = {
		{ "pid", 'p', 0, OptionArg.INT, ref target_pid, "target PID", "PID" },
		{ "data", 'd', 0, OptionArg.STRING, ref data, "string passed to the embedded hello payload", "DATA" },
		{ "exec", 'x', 0, OptionArg.STRING, ref command, "shell command to execute in a forked child", "COMMAND" },
		{ "commercial-wrapper", 0, 0, OptionArg.NONE, ref commercial_wrapper, "inject the embedded commercial wrapper scanner", null },
		{ "version", 0, 0, OptionArg.NONE, ref output_version, "Output version information and exit", null },
		{ null }
	};

	private static int main (string[] args) {
#if !WINDOWS
		Posix.setsid ();
#endif

		Environment.init ();

		try {
			var ctx = new OptionContext ();
			ctx.set_help_enabled (true);
			ctx.add_main_entries (code_options, null);
			ctx.parse (ref args);

			if (output_version) {
				print ("%s\n", version_string ());
				return 0;
			}
		} catch (OptionError e) {
			printerr ("%s\n", e.message);
			printerr ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
			return 1;
		}

		if (target_pid <= 0) {
			printerr ("PID must be specified and greater than zero\n");
			return 2;
		}

		bool has_command = command != null;
		bool has_data = data != null;

		int selected_modes = (has_command ? 1 : 0) + (has_data ? 1 : 0) + (commercial_wrapper ? 1 : 0);
		if (selected_modes > 1) {
			printerr ("--data, --exec, and --commercial-wrapper are mutually exclusive\n");
			return 6;
		}

		if (has_command && command == "") {
			printerr ("Command must not be empty\n");
			return 7;
		}

		application = new Application ((uint) target_pid, data ?? "", command, commercial_wrapper);
		return application.run ();
	}

	namespace Environment {
		public extern void init ();
	}

	private sealed class Application : Object {
		public uint pid {
			get;
			construct;
		}

		public string data {
			get;
			construct;
		}

		public string? command {
			get;
			construct;
		}

		public bool commercial_wrapper {
			get;
			construct;
		}

		private MainLoop loop;
		private int exit_code;
		private LinuxHelperBackend? helper;

		public Application (uint pid, string data, string? command, bool commercial_wrapper) {
			Object (
				pid: pid,
				data: data,
				command: command,
				commercial_wrapper: commercial_wrapper
			);
		}

		public int run () {
			Idle.add (() => {
				start.begin ();
				return false;
			});

			loop = new MainLoop ();
			loop.run ();

			return exit_code;
		}

		private async void start () {
#if LINUX
			try {
				helper = new LinuxHelperBackend ();
				if (commercial_wrapper) {
					yield helper.inject_commercial_wrapper_code (pid, null);
					print ("injected commercial-wrapper pid=%u\n", pid);
				} else if (command != null) {
					yield helper.inject_exec_code (pid, command, null);
					print ("executed command pid=%u\n", pid);
				} else {
					yield helper.inject_hello_code (pid, data, null);
					print ("injected code pid=%u\n", pid);
				}
				exit_code = 0;
			} catch (GLib.Error e) {
				printerr ("%s\n", e.message);
				exit_code = 3;
			}

			if (helper != null) {
				try {
					yield helper.close (null);
				} catch (IOError e) {
					printerr ("Unable to close helper: %s\n", e.message);
					if (exit_code == 0)
						exit_code = 4;
				}
				helper = null;
			}
#else
			printerr ("frida-code-inject is only supported on Linux/Android\n");
			exit_code = 5;
#endif

			Idle.add (() => {
				loop.quit ();
				return false;
			});
		}
	}
}
