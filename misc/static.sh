#!/bin/sh

APPNAME="ppbd"
SCRIPT="ppb.pl"

. ~/.staticperlrc

~/staticperl mkapp $APPNAME --boot ../main.pl \
-MCwd \
-MEnv \
-Msort.pm \
-Mvars \
-Mutf8 \
-Mutf8_heavy.pl \
-MConfig \
-MConfig_heavy.pl \
-MErrno \
-MFcntl \
-MPOSIX \
-MSocket \
-MCarp \
-MEncode \
-MEncode::Unicode \
-MScalar::Util \
-MTime::HiRes \
-MStorable \
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
-MClone \
-MJSON::XS \
-MJSON \
-MSys::Syslog \
-MObject::Accessor \
-MFeersum \
-MMongoDB \
-MDateTime \
-MDateTime::Tiny \
-Mboolean \
-MClass::Load::XS \
-MIO::File \
-MHTTP::Body \
-MDigest::JHash \
--strip ppi \
--allow-dynamic \
--usepacklists \
--incglob '/unicore/**.pl' \
--add "../$SCRIPT $SCRIPT"
