# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2000-2003 Andrea Sterbini, a.sterbini@flashnet.it
# Copyright (C) 2001-2003 Peter Thoeny, peter@thoeny.com
# Copyright (C) 2003      Nathan Ollerenshaw, chrome@stupendous.net
# Copyright (C) 2006-2009 Sven Dowideit, SvenDowideit@WikiRing.com
# Copyright (C) 2010      Bryan Thale, bryan.thale@motorola.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

=begin TML

---+ package LocalTimePlugin

Implements the %<nop>LOCALTIME% macro to display a formatted date and time 
possibly adjusted for a given time zone.

Plugin Version: $Rev$

=cut

package Foswiki::Plugins::LocalTimePlugin;

use strict;

require Foswiki::Func;
require Foswiki::Plugins;

# $VERSION is referenced by Foswiki and is the only global variable that
# *must* exist in this package.  This should always be '$Rev$'
# so that Foswiki can determine the checked-in status of the plugin.  It is
# used by the build automation tools, so you should leave it alone.
our $VERSION = '$Rev$';

# $RELEASE is a free-form string used to identify "releases" of a plugin
# independent of the build system.  It is *not* used by the build automation
# tools, but *is* reported as part of the version number by %PLUGINDESCRIPTIONS%.
#
# LocalTimePlugin uses a major.minor.patch numbering scheme for releases.
# 'major' releases indicate a break in compatibility with previous versions
# such as the removal of deprecated features.  'minor' releases indicate
# backward-compatible changes to or new additions of functionality.  'patch'
# releases indicate bug fixes or other internal implementation changes that
# aren't visible to users of the package.
our $RELEASE = '1.1.1';

# One line description of this plugin reported by %PLUGINDESCRIPTIONS%
our $SHORTDESCRIPTION =
  'Provides the %<nop>LOCALTIME% macro to display a formatted date and/or time';

# LocalTimePlugin uses the normal Foswiki preferences mechanism for settings
our $NO_PREFS_IN_TOPIC = 1;

# Flag indicating whether we are running in a mod_perl2 environment.  This value
# won't change once set since it is an attribute of the process environment.
my $modperl2;

=begin TML

---++ initPlugin( $topic, $web, $user, $installWeb ) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin topic is in

Initializes and installs the handler routine for the %<nop>LOCALTIME% macro.

Returns: 1 on success, 0 on failure

=cut

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    my $min_api_version = 2.0;
    if ( $Foswiki::Plugins::VERSION < $min_api_version ) {

        # Oops! We are not compatible with this version of the Plugin API
        Foswiki::Func::writeWarning( "Version $RELEASE of "
              . __PACKAGE__
              . " requires at least version $min_api_version of the Foswiki "
              . "Plugin API.  Current version is $Foswiki::Plugins::VERSION" );
        return 0;
    }

    _debugEntryPoint( "$web.$topic", 'initPlugin',
        { user => $user, installWeb => $installWeb } );

    unless ( defined($modperl2) ) {

        # Check if we're running under mod_perl2
        my $software = '';
        my $version  = '';
        if ( $ENV{MOD_PERL} ) {
            ( $software, $version ) =
              $ENV{MOD_PERL} =~ m{^(\S+)/(\d+(?:[\.\_]\d+)+)};
            $version         =~ s/_//g;
            $version         =~ s/(\.[^.]+)\./$1/g;
        }

        $modperl2 = ( $software eq 'mod_perl' && $version >= 1.99922 );
    }

    _debug( "$web.$topic",
        ( $modperl2 ? 'mod_perl2' : 'CGI' ) . ' environment detected' );

    # Install our macro handler for %LOCALTIME%
    Foswiki::Func::registerTagHandler( 'LOCALTIME', \&handleLocalTime );

    # Plugin correctly initialized
    _debug( "$web.$topic", "Plugin initialized" );
    return 1;
}

=begin TML

---++ handleLocalTime( $session, $params, $theTopic, $theWeb ) -> $string

Process the %<nop>LOCALTIME% macro and return the desired date/time as a 
formatted string.  Uses the Date::Handler and Date:Parse Perl modules.

   * =$session= - a reference to the Foswiki session object
   * =$params= - a reference to a Foswiki::Attrs object containing the macro parameters
      * =DEFAULT= - (optional) the desired timezone in which to render the date/time. Defaults to the LOCALTIMEPLUGIN_TIMEZONE preference setting or UTC.
      * =datetime= - (optional) the date/time to display, assumed to be in UTC unless the string contains a timezone identifier.  Defaults to the current date and time
      * =format= - (optional) the desired output format specifier string. Defaults to the LOCALTIMEPLUGIN_DATEFORMAT preference or to the Foswiki '$longdate' format
      * =locale= - (optional) the desired locale definition to use when displaying the date and time. Defaults to the LOCALTIMEPLUGIN_LOCALE preference or to the site's locale defined in $Foswiki::cfg{Site}{Locale}
      * =fromtopic= - (optional, deprecated) the web.topic from which to set the value of the TIMEZONE variable, use the LOCALTIMEPLUGIN_TIMEZONE preference instead
      * =dateGMT= - (optional, deprecated) the same as the =datetime= parameter, use =datetime= instead
   * =$theTopic= - the name of the topic being processed
   * =$theWeb= - the name of the web containing the topic being processed

Returns: the date and/or time as a formatted string or an error message upon failure

=cut

sub handleLocalTime {
    my ( $session, $params, $theTopic, $theWeb ) = @_;

    _debugEntryPoint( "$theWeb.$theTopic", 'handleLocalTime', $params );

    eval {
        require Date::Handler;
        require Date::Parse;
    };
    if ($@) {
        # Capture error message up to the first newline
        $@ =~ /^(.*)/;
        my $msg = "Error: Can't load required modules";
        _warning( "$theWeb.$theTopic", "$msg ($1)" );
        return "%RED%$msg%ENDCOLOR%";
    }

    my $warning = 'invoked macro LOCALTIME';
    my $timezone =
         $params->{_DEFAULT}
      || &Foswiki::Func::getPreferencesValue('LOCALTIMEPLUGIN_TIMEZONE')
      || 'UTC';

    my $datetime = $params->{datetime};

    my $format =
         $params->{format}
      || &Foswiki::Func::getPreferencesValue('LOCALTIMEPLUGIN_DATEFORMAT')
      || '$longdate';

    my $locale =
         $params->{locale}
      || &Foswiki::Func::getPreferencesValue('LOCALTIMEPLUGIN_LOCALE')
      || ( $Foswiki::cfg{UseLocale} ? $Foswiki::cfg{Site}{Locale} : 'en_US' );

    if ( !defined( $params->{datetime} ) && defined( $params->{dateGMT} ) ) {
        _warning( "$theWeb.$theTopic",
            "$warning with deprecated parameter 'dateGMT'" );
        $datetime = $params->{dateGMT};
    }

    if ( !defined( $params->{_DEFAULT} ) && defined( $params->{fromtopic} ) ) {
        _warning( "$theWeb.$theTopic",
            "$warning with deprecated parameter 'fromtopic'" );

        # Fetch the TIMEZONE setting from the indicated topic
        my ( $web, $topic ) =
          Foswiki::Func::normalizeWebTopicName( $theWeb, $params->{fromtopic} );
        Foswiki::Func::pushTopicContext( $web, $topic );
        my $zone = Foswiki::Func::getPreferencesValue('TIMEZONE');
        Foswiki::Func::popTopicContext();
        $timezone = $zone if defined($zone);
    }

    # Expand Foswiki convenience tokens into fully tokenized formats
    $format =~
      s|\$lon(gdate)?|$Foswiki::cfg{DefaultDateFormat} - \$hour:\$min|g;
    $format =~ s|\$rcs|\$year/\$mo/\$day \$hour:\$min:\$sec|g;
    $format =~ s|\$iso|\$year-\$mo-\$dayT\$hour:\$min:\$sec\$tziso|g;
    $format =~
      s|\$htt(p)?|\$wday, \$day \$month \$year \$hour:\$min:\$sec \$tz|g;
    $format =~
      s|\$ema(il)?|\$wday, \$day \$month \$year \$hour:\$min:\$sec \$tz|g;
    $format =~
      s|\$rfc|\$wday, \$day \$month \$year \$hour:\$min:\$sec \$tziso|g;

    # Convert Foswiki tokens to strftime format specifiers
    $format =~ s|\$sec(onds?)?|%S|g;
    $format =~ s|\$min(utes?)?|%M|g;
    $format =~ s|\$hou(rs?)?|%H|g;
    $format =~ s|\$day|%d|g;
    $format =~ s|\$wda(y)?|%a|g;
    $format =~ s|\$dow|%w|g;
    $format =~ s|\$wee(k)?|%V|g;
    $format =~ s|\$mon(th)?|%b|g;
    $format =~ s|\$mo|%m|g;
    $format =~ s|\$yea(r)?|%Y|g;
    $format =~ s|\$ye|%y|g;
    $format =~ s|\$epo(ch)?|%s|g;
    $format =~ s|\$tzi(so)?|%z|g;
    $format =~ s|\$tz|%Z|g;
    $format = Foswiki::Func::decodeFormatTokens($format);

    my $time = time;
    if ( defined($datetime) ) {

        # Figure out the date string the user gave us
        my $str = $datetime;

        # Get rid of leading and trailing decorations
        $str =~ s|^\s*([a-zA-Z]+,\s*)?||;
        $str =~ s|(\s*\([^\)]\))?\s*$||;

        # Normalize date component
        $str =~
s!^(\d{1,2})([-/ :\.])([a-zA-Z]{3,})\2(\d{4}|\d{2})([^:\.])!$1-$3-$4$5!;
        $str =~ s!^(\d{4})([-/ :\.])(\d{1,2})\2(\d{1,2})!$1-$3-$4!;
        $str =~ s!^(\d{4}-\d{1,2}-\d{1,2})T$!$1!;
        $str =~ s!^(\d{4})[-/ :\.](\d{1,2})$!$1-$2-1!;
        $str =~ s!^(\d{4}|\d{2})$!$1-1-1!;

        # Normalize time component
        $str =~
          s!( - | |T|\.)(\d{1,2})([\.:])(\d{1,2})\3(\d{1,2}(\.\d+)?)! $2:$4:$5!;
        $str =~ s!( - | |T|\.)(\d{1,2})([\.:])(\d{1,2})! $2:$4!;

        # Parse this sucker
        $time = Date::Parse::str2time($str);
        unless ($time) {
            my $msg = "unrecognized date/time: $datetime";
            _warning( "$theWeb.$theTopic", "$warning with $msg" );
            return "%RED%$msg%ENDCOLOR%";
        }
    }

    my $date = new Date::Handler(
        {
            date      => $time,
            time_zone => $timezone,
            locale    => $locale
        }
    );

    return (
        $modperl2
        ? _callModPerl2Helper( $date, $format, "$theWeb.$theTopic" )
        : $date->TimeFormat($format)
    );
}

=begin TML

---++ _callModPerl2Helper( $date, $format, $topic ) -> $string

Invoke the mod_perl2-safe helper script to format and return the date.  Uses the
APR::Base64 Perl module.

   * =$date= - a reference to a Date::Handler object containing the date to format
   * =$format= - the desired format string
   * =$topic= - the topic containing the %<nop>LOCALTIME% macro

Returns: the date and/or time as a formatted string

=cut

sub _callModPerl2Helper {
    my ( $date, $format, $topic ) = @_;

    eval { require APR::Base64; };
    if ($@) {
        # Capture error message up to the first newline
        $@ =~ /^(.*)/;
        my $msg = "Error: Can't load required modules";
        _warning( $topic, "$msg ($1)" );
        return "%RED%$msg%ENDCOLOR%";
    }

    my $time     = $date->Epoch();
    my $timezone = $date->TimeZone();
    my $locale   = $date->Locale();

    my $utc = Foswiki::Time::formatTime( $time, '$iso', 'gmtime' );
    _debugEntryPoint(
        $topic,
        '_callModPerl2Helper',
        {
            date     => $utc,
            format   => $format,
            locale   => $locale,
            timezone => $timezone
        }
    );

    # Path to the Perl interpreter
    my $perlCmd =
         $Foswiki::cfg{Tools}{perlCmd}
      || $Foswiki::cfg{Plugins}{LocalTimePlugin}{perlCmd}
      || 'perl';

    # Create a temporary helper script to pass to the external Perl interpreter
    my $scriptFile = new File::Temp(
        TEMPLATE => 'LocalTimePluginXXXXXXXXXX',
        DIR      => Foswiki::Func::getWorkArea('LocalTimePlugin'),
        UNLINK   => !Foswiki::Func::getPreferencesFlag('LOCALTIMEPLUGIN_DEBUG'),
        SUFFIX   => '.pl'
    );

    # Protect against Perl code insertion attacks by Base64 encoding the text
    # the user gave us
    $timezone = APR::Base64::encode($timezone);
    $locale   = APR::Base64::encode($locale);
    $format   = APR::Base64::encode($format);
    my $helperScript = <<EOT;
#!/usr/lib/perl
use strict;
use warnings;
use APR::Base64;
use Date::Handler;
my \$timezone = APR::Base64::decode( '$timezone' );
my \$locale = APR::Base64::decode( '$locale' );
my \$format = APR::Base64::decode( '$format' );
my \$date = new Date::Handler( { date => $time, 
                                 time_zone => \$timezone,
                                 locale => \$locale } );
print \$date->TimeFormat( \$format );

EOT

    Foswiki::Func::saveFile( "$scriptFile", $helperScript );

    # Execute our helper script
    my ( $output, $status ) =
      Foswiki::Sandbox->sysCommand( "$perlCmd %HELPERSCRIPT|F%",
        HELPERSCRIPT => "$scriptFile" );

    if ($status) {
        _warning( $topic, "Error $status: $scriptFile returned '$output'" );
        return "%RED%Error: $output%ENDCOLOR%";
    }
    else {
        _debug( $topic, "$scriptFile returned ('$output', $status)" );
    }

    return $output;
}

=begin TML

---++ _warning( $topic, $msg )

Log a warning and debug message. The topic is prepended to the message.

   * =$topic= - the web.topic being processed
   * =$msg= - the message text to write to the warning and debug logs

=cut

sub _warning {
    my ( $topic, $msg ) = @_;
    Foswiki::Func::writeWarning( $topic, $msg );
    _debug( $topic, $msg );
}

=begin TML

---++ _debugEntryPoint( $topic, $func, $args )

Write a function entry message to the debug log if debug logging is enabled.
The topic is prepended to the message.

   * =$topic= - the web.topic being processed
   * =$func= - the name of the function being logged
   * =$args= - a reference to a hash containing the arguments passed to $func

=cut

sub _debugEntryPoint {
    if ( Foswiki::Func::getPreferencesFlag('LOCALTIMEPLUGIN_DEBUG') ) {
        my ( $topic, $func, $args ) = @_;
        my $msg = '';
        foreach my $key ( sort keys %$args ) {
            $msg .= ", $key=>'$args->{$key}'";
        }
        $msg =~ s/^, //;
        _debug( $topic, "$func( $msg )" );
    }
}

=begin TML

---++ _debug( $topic, $msg )

Write the supplied message to the debug log if debug logging is enabled. The
Perl package name and topic are prepended to the message.

   * =$topic= - the web.topic being processed
   * =$msg= - the message text to write to the debug log

=cut

sub _debug {
    if ( Foswiki::Func::getPreferencesFlag('LOCALTIMEPLUGIN_DEBUG') ) {
        my ( $topic, $msg ) = @_;
        Foswiki::Func::writeDebug( __PACKAGE__, $topic, $msg );
    }
}

1;
