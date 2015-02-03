#!/bin/sh

APPNAME="ppbd"
STRIP="ppi"
LINKTYPE="static" # "allow-dynamic"

. ~/.staticperlrc

~/staticperl mkapp $APPNAME --boot ../src/main.pl \
-Msort.pm \
-Mvars \
-Mutf8 \
-Mutf8_heavy.pl \
-MErrno \
-MFcntl \
-MPOSIX \
-MSocket \
-MCarp \
-MEncode \
-Mcommon::sense \
-MEV \
-MGuard \
-MAnyEvent \
-MAnyEvent::Handle \
-MAnyEvent::Socket \
-MAnyEvent::Impl::EV \
-MAnyEvent::Impl::Perl \
-MAnyEvent::Util \
-MAnyEvent::Log \
-MPod::Usage \
-MGetopt::Long \
-MFile::Spec::Functions \
-MJSON::XS \
-MSys::Syslog \
-MFeersum \
-MIO::File \
-MHTTP::Body \
-MMIME::Type::FileName \
-MUnQLite \
-MMath::BigInt \
--strip ${STRIP} \
--${LINKTYPE} \
--usepacklists \
--add "../src/app/feersum.pl app/feersum.pl" \
--add "../src/backend/feersum.pl backend/feersum.pl" \
--add "../src/modules/PPB/DB/UnQLite.pm PPB/DB/UnQLite.pm" \
--add "../src/modules/PPB/Feersum/Tiny.pm PPB/Feersum/Tiny.pm" \
