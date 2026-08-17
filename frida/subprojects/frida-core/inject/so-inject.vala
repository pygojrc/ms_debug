namespace Frida.Inject {
	private static Application application;

	private static int target_pid = -1;
	private static string? library_path;
	private static string? entrypoint;
	private static string? data;
	private static bool output_version;

	const OptionEntry[] so_options = {
		{ "pid", 'p', 0, OptionArg.INT, ref target_pid, "target PID", "PID" },
		{ "library", 'l', 0, OptionArg.FILENAME, ref library_path, "shared library to inject", "PATH" },
		{ "entrypoint", 'e', 0, OptionArg.STRING, ref entrypoint, "entrypoint function to call; omit for load-only dlopen", "SYMBOL" },
		{ "data", 'd', 0, OptionArg.STRING, ref data, "string passed to the entrypoint", "DATA" },
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
			ctx.add_main_entries (so_options, null);
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

		if (library_path == null || library_path == "") {
			printerr ("Path to shared library must be specified\n");
			return 3;
		}

		unowned string path = library_path;
		string symbol = entrypoint ?? "";
		string entrypoint_data = data ?? "";

		if (!FileUtils.test (path, FileTest.EXISTS)) {
			printerr ("Shared library does not exist: %s\n", path);
			return 4;
		}

		uint8[] blob_data;
		try {
			FileUtils.get_data (path, out blob_data);
		} catch (FileError e) {
			printerr ("Unable to read shared library: %s\n", e.message);
			return 4;
		}

		application = new Application ((uint) target_pid, new Bytes.take ((owned) blob_data), symbol, entrypoint_data);
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

		public Bytes library_blob {
			get;
			construct;
		}

		public string entrypoint {
			get;
			construct;
		}

		public string data {
			get;
			construct;
		}

		private MainLoop loop;
		private int exit_code;
		private Injector? injector;

		public Application (uint pid, Bytes library_blob, string entrypoint, string data) {
			Object (
				pid: pid,
				library_blob: library_blob,
				entrypoint: entrypoint,
				data: data
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
			try {
				injector = Injector.new ();
				uint id = yield injector.inject_library_blob (pid, library_blob, entrypoint, data);
				if (entrypoint == "")
					print ("injected id=%u load-only\n", id);
				else
					print ("injected id=%u\n", id);
				exit_code = 0;
			} catch (GLib.Error e) {
				printerr ("%s\n", e.message);
				exit_code = 6;
			}

			if (injector != null) {
				try {
					yield injector.close ();
				} catch (IOError e) {
					printerr ("Unable to close injector: %s\n", e.message);
					if (exit_code == 0)
						exit_code = 7;
				}
				injector = null;
			}

			Idle.add (() => {
				loop.quit ();
				return false;
			});
		}
	}
}
