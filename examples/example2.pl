#!/usr/bin/perl

# (c) 2001 ph15h

# example2.pl
#
# this example actually is a default application, you may copy
# or link in your script directory, while your application
# class is the same directory.
#
# this implementation is quite usefull, because you can do all your
# definitions for your cgi-script application (e.g. set global library
# path) inside the main script routine.

use lib qw( ../../  );

{
  my ( $package ) = ( $0 =~ /\/?(\w+)\.pl/i );
  require "$package.pm";
  my $script_class = new $package;
  run $script_class;
}


