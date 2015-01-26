# perl-pastebin-daemon
Standalone HTTP pastebin service writen in Perl

# Dependencies
This software requires next modules and libraries installed
via CPAN or other Perl package management system:

* EV
* AnyEvent
* Feersum
* HTTP::Body
* HTML::Entities
* JSON::XS
* File::Spec
* Getopt::Long
* Math::BigInt
* UnQLite
* MIME::Type::FileName
* Sys::Syslog (optional)

# Usage

The program is splitted in three major parts:

* runner (main.pl)
* backend (backend/feersum.pl)
* application (app/feersum.pl)

To start the program type in console:

```
shell> perl src/main.pl
```

# Options

```
shell> perl src/main.pl --help
Allowed options:
  --help [-h]              prints this information
  --version                prints program version
  --listen [-l] arg        IP:PORT for listener
                           - default: "127.0.0.1:28950"
  --backend [-b] arg       backend name (default: feersum)
  --app [-a] arg           application name (default: feersum)
  --background [-B]        run process in background
                           - default: run in foreground (disables logging)
                           - hint: use --logfile / --enable-syslog for logging
  --home [-H] arg          working directory after fork
                           - default: root directory
  --www-dir [-W] arg       www directory with index.html
  --debug                  be verbose
  --verbose                be very verbose
  --quiet [-q]             be silence, disables logging
  --enable-syslog          enable logging via syslog (default: disabled)
  --syslog-facility arg    syslog's facility (default: LOG_DAEMON)
  --logfile [-L] arg       path to log file (default: stdout)
  --pidfile [-P] arg       path to pid file (default: none)
```

# Development & Customization

The runner script <code>main.pl</code> was made to be independent 
on backend code. To create your own backend you have to 
create file in backend directory. For instance, for Twiggy, 
you may create file <code>src/backend/twiggy.pl</code>. 
Then run the server in this way:

```
shell> perl src/main.pl --backend=twiggy
```

Note that extention of the file was ommited, as well as full path to
file.
