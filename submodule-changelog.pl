#!/usr/bin/perl

use warnings;
use strict;

my $owner   = shift || die "Usage: $0 <owner> <version>\n";
my $version = shift || die "Usage: $0 <owner> <version>\n";

my $mod;

print "Build $version\n\n";

while (<STDIN>) {
    if (/Entering '(.*?)'(.*)$/) {
        $mod=$1;
        print "# $mod$2\n";
    } else {
        die "What module is this?" unless defined $mod;
        if (/^commit ([A-Fa-z0-9]+)/) {
            $_ = "commit $owner/$mod\@$1\n";
        }

        print " "x8, $_;
    }
}
