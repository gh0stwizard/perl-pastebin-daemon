#!/usr/bin/perl

# ppbd - perl pastebin daemon
#
# This is free software; you can redistribute it and/or modify it 
# under the same terms as the Perl 5 programming language system itself.

use strict;
use warnings;
use POSIX ();
use Cwd ();
use Getopt::Long qw(:config no_ignore_case bundling);
use vars qw($PROGRAM_NAME $VERSION);
$PROGRAM_NAME = "ppb.pl"; $VERSION  = '0.10';

my $retval = GetOptions
(
  \my %options,
  'help|h',
  'version',
  'verbose|v',
  'pidfile|P=s',
  'home|H=s',
  'fork',
  'logfile|L=s',
  'enable-syslog',
  'syslog-facility=s',
  'quiet',
  'listen=s',
  'db_server|S=s',
  'db_name|N=s',
  'db_coll|C=s',
  'indexfile|I=s',
  'enable-vimbow',
  'vimbow=s',
);

if (defined $retval and !$retval) {
    # unknown option workaround
    print "use --help for help\n";
    exit 1;
} elsif (exists $options{'help'}) {
    &print_help();
    exit 0;
} elsif (exists $options{'version'}) {
    print "$PROGRAM_NAME version $VERSION\n";
    exit 0;
}

# fix relative paths to absolute as needed
my $pwd = Cwd::abs_path(Cwd::cwd);

for my $opt (qw(logfile home pidfile indexfile)) {
    next if (!exists $options{$opt});
    next if ($options{$opt} =~ m/^\//);
    $options{$opt} = join('/', $pwd, $options{$opt});
}

# pidfile lock
if (exists $options{'pidfile'}) {
    -e $options{'pidfile'} 
        and die "pidfile \`$options{'pidfile'}\' already exits";

    $ENV{'PPB_PIDFILE'} = $options{'pidfile'};
}

# HTTP server settings
if (exists $options{listen}) {
    $ENV{PPB_LISTEN} = $options{listen};
}

# MongoDB server settings
if (exists $options{db_server}) {
    $ENV{PPB_DBSERV} = $options{db_server};
}

if (exists $options{db_name}) {
    $ENV{PPB_DBNAME} = $options{db_name};
}

if (exists $options{db_coll}) {
    $ENV{PPB_DBCOLL} = $options{db_coll};
}

# HTTP index.html file
if (exists $options{indexfile}) {
    $ENV{PPB_INDEX} = $options{indexfile};
}

# VimBow support
if (exists $options{'vimbow'}) {
    $ENV{PPB_VIMBOW} = $options{'vimbow'};
}

if (exists $options{'enable-vimbow'}) {
    $ENV{PPB_VIMBOW_ENABLED} = 1;
}


# Set up AnyEvent::Log environment variable.
$ENV{PERL_ANYEVENT_LOG} = &ae_log_string();

# Workaround for run program via staticperl vs common perl.
#
# Explaination: Common perl after fork was chrooted to real '/',
# but there are very high possibility that user just testing this
# program and do not imported MyService/*.pm to PERL5LIB. 
# So, we put real path to MyService directory into @INC. After
# that all modules in MyService will be successfuly loaded :-)
if ($0 ne '-e') { # :-\ staticperl uses '-e' as $0
    my $filepath = $0;
    $filepath =~ s/\/.*$//m;
    $filepath = join('/', $pwd, $filepath);
    unshift @INC, $pwd, $filepath;
}

if (exists $options{'fork'}) {
    &daemonize();
}

# Start the main program after fork. This is best practicle for EV-based
# applications.
unless (my $rv = do $PROGRAM_NAME) {
    warn "couldn't parse $PROGRAM_NAME: $@" if $@;
    warn "couldn't do $PROGRAM_NAME: $!" unless defined $rv;
    warn "couldn't run $PROGRAM_NAME" unless $rv;
}

exit 0;

# /-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|

# perldoc AnyEvent::Log
sub ae_log_string() {
    # AnyEvent::Log's control via environment variables
    my $AE_LOG = (exists $options{'verbose'})
        ? 'filter=trace'
        : (exists $options{'debug'})
            ? 'filter=debug'
            : 'filter=note'; # default log level

    if (exists $options{'logfile'}) {
        # enable syslog + logfile
        if (exists $options{'enable-syslog'}) {
            $AE_LOG .= sprintf ":log=file=%s=+%syslog:%syslog=%s",
                $options{'logfile'},
                (exists $options{'syslog-facility'}) 
                    ? $options{'syslog-facility'}
                    : 'LOG_DAEMON';
        } else {
            $AE_LOG .= sprintf ":log=file=%s", $options{'logfile'};
        }
    } elsif (exists $options{'enable-syslog'}) {
        # syslog
        $AE_LOG .= sprintf ":log=syslog=%s",
            $options{'syslog-facility'}
                ? $options{'syslog-facility'}
                : 'LOG_DAEMON';
    } elsif (exists $options{'quiet'}) {
        # disable logging totally
        $AE_LOG .= ':log=nolog';
    } else {
        # print to stdout
        $AE_LOG .= ':log=';
    }

    return $AE_LOG;
}

sub daemonize() {
    # chroot
    my $rootdir = ($options{'home'}) ? $options{'home'} : '/';
    chdir ($rootdir)            || die "chdir \`$rootdir\': $!";
    # Due to bug/feature of perl we do not close standard handlers.
    # Otherwise, Perl will complain and throw warning messages 
    # about reopenning 0, 1 and 2 filehandles.
    open(STDIN, "< /dev/null")    || die "can't read /dev/null: $!";
    open(STDOUT, "> /dev/null")   || die "can't write /dev/null: $!";
    defined(my $pid = fork())     || die "can't fork: $!";
    exit if $pid;
    (POSIX::setsid() != -1)       || die "Can't start a new session: $!";
    open(STDERR, ">&STDOUT")      || die "can't dup stdout: $!";
}

sub print_help() {
    printf "Allowed options:\n";

    my $h = "  %-32s %-45s\n";

    printf $h, "-h [--help]", "show this usage information";
    printf $h, "--version", "show version information";
    printf $h, "-v [--verbose]", "be more verbose";
    printf $h, "--fork", "fork server process";

    printf $h, "-H [--home] arg", "working dir when fork";
    printf $h, "", "- default is /";

    printf $h, "--quiet", "disable logging";
    printf $h, "-P [--pidfile] arg", "full path to pidfile";
    printf $h, "-L [--logfile] arg", "full path to logfile (if not set, log to stdout)";
    printf $h, "--enable-syslog", "log via syslog (disables logging to file)";
    printf $h, "--syslog-facility", "syslog facility (default is local7)";

    printf $h, "--listen arg", "comma separated list of ip:port to listen on";
    printf $h, "", "- default is 127.0.0.1:28950";
    
    printf $h, "-I [--indexfile] arg", "full path to skin directory";
    printf $h, "", "- default is /var/www/ppb/index.html";

    printf $h, "-S [--db_server] arg", "mongodb ip:port server address and port";
    printf $h, "", "- default is 127.0.0.1:27017";
    printf $h, "-N [--db_name] arg", "mongodb database";
    printf $h, "", "- default is ppb";
    printf $h, "-C [--db_coll] arg", "mongodb collection name in db";
    printf $h, "", "- default is posts";
}
