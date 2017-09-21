#!/usr/bin/perl
# ---------------------------------------
# Program : exif2picture.pl
#
# Copyright (C) 2012-2017 Klaus Tockloth
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# Contact (eMail): <freizeitkarte@googlemail.com>
#
# Program code formatted with "perltidy".
#
# Tools:
# - ImageMagick: http://www.imagemagick.org/script/index.php
# - ExifTool: http://owl.phy.queensu.ca/~phil/exiftool/
# -----------------------------------------

use strict;
use warnings;
use English '-no_match_vars';

use Cwd;
use File::Copy;
use File::Path;
use File::Basename;
use Getopt::Long;

# pseudo constants
my $EMPTY = q{};

my $VERSION = '0.3 - 2017/09/21';

my ( $appbasename, $appdirectory, $appsuffix ) = fileparse ( $0, qr/\.[^.]*/ );

my $programName = basename ( $PROGRAM_NAME );
my $programInfo = "$programName - Exif to Picture";
printf { *STDOUT } ( "\n%s, %s\n\n", $programInfo, $VERSION );

# OS X = 'darwin'; Windows = 'MSWin32'; Linux = 'linux'; FreeBSD = 'freebsd'
# printf { *STDOUT } ( "OSNAME = %s\n", $OSNAME );
# printf { *STDOUT } ( "PERL_VERSION = %s\n", $PERL_VERSION );
# printf { *STDOUT } ( "BASEPATH = %s\n\n", $BASEPATH );

# command line parameters
my $help       = $EMPTY;
my $listexif   = $EMPTY;
my $rawdata    = $EMPTY;
my $cfgfile    = $appbasename . '.cfg';
my $fileprefix = "anno_";

my $command                 = $EMPTY;
my $ImageMagick_command_raw = $EMPTY;
my $ImageMagick_command     = $EMPTY;
my $path                    = $EMPTY;
my %exifdata;

# get the command line parameters
GetOptions ( 'h|?' => \$help, 'listexif' => \$listexif, 'rawdata' => \$rawdata, 'cfgfile=s' => \$cfgfile, 'fileprefix=s' => \$fileprefix );

if ( ( $help ) || ( ( $#ARGV + 1 ) < 1 ) ) {
  show_help ();
}

# build picture (source file) list
my @sourcefiles = glob ( "@ARGV" );

# read configuration for ImageMagick
my $cfgfile_found = 0;
read_configuration ();

my $sourcefile      = $EMPTY;
my $destinationfile = $EMPTY;
foreach my $item ( @sourcefiles ) {
  $sourcefile = $item;
  print "processing $sourcefile ...\n";

  # replace [SOURCEFILE]
  $ImageMagick_command = $ImageMagick_command_raw;
  $ImageMagick_command =~ s/\[SOURCEFILE\]/\"$sourcefile\"/;

  # replace [DESTINATIONFILE]
  $destinationfile = $fileprefix . basename ( $sourcefile );
  $ImageMagick_command =~ s/\[DESTINATIONFILE\]/\"$destinationfile\"/;

  read_exifdata ();

  if ( !$listexif ) {
    annotate_picture ();
  }
}

exit ( 0 );


# -----------------------------------------
# Systembefehl ausfuehren
# -----------------------------------------
sub process_command {

  my $temp_string = $EMPTY;
  my $t0          = time ();

  printf { *STDOUT } ( "\n%s\n", $command );

  my @args             = ( $command );
  my $systemReturncode = system ( @args );

  # The return value is the exit status of the program as returned by the wait call.
  # To get the actual exit value, shift right by eight (see below).
  if ( $systemReturncode != 0 ) {
    printf { *STDERR } ( "Warning: system($command) failed: $?\n" );

    if ( $systemReturncode == -1 ) {
      printf { *STDERR } ( "Failed to execute: $!\n" );
    }
    elsif ( $systemReturncode & 127 ) {
      $temp_string = sprintf ( "Child died with signal %d, %s coredump\n", ( $systemReturncode & 127 ), ( $systemReturncode & 128 ) ? 'with' : 'without' );
      printf { *STDERR } $temp_string;
    }
    else {
      $temp_string = sprintf ( "Child exited with value %d\n", $systemReturncode >> 8 );
      printf { *STDERR } $temp_string;
    }
  }

  my $t1 = time ();

  my $elapsed          = $t1 - $t0;
  my $actionReturncode = $systemReturncode >> 8;
  printf { *STDERR } ( "\nElapsed, System-RC, Action-RC: $elapsed, $systemReturncode, $actionReturncode\n\n" );

  return $systemReturncode;
}


# -----------------------------------------
# Trim whitespaces from the start and end of the string.
# -----------------------------------------
sub trim {

  my $string = shift;

  $string =~ s/^\s+//;
  $string =~ s/\s+$//;

  return ( $string );
}


# -----------------------------------------
# Read configuration from file.
# CodeSnippet from:
# - Perl Kochbuch, O'Reilly, 2. Auflage
# - 8.16 Konfigurationsdateien einlesen
# -----------------------------------------
sub read_configuration {

  if ( !( -s $cfgfile ) ) {
    return;
  }
  $cfgfile_found = 1;

  open ( my $CONFIG_FILE, '<', $cfgfile ) or die ( "Error opening cfgfile \"$cfgfile\": $!\n" );

  while ( <$CONFIG_FILE> ) {
    chomp ();    # no newline
    s/##.*//;    # no comments
    s/^\s+//;    # no leading white
    s/\s+$//;    # no trailing white
    next unless length ();    # anything left?
    $ImageMagick_command_raw = $ImageMagick_command_raw . $_ . ' ';
  }

  close ( $CONFIG_FILE );

  # print "ImageMagick_command_raw: $ImageMagick_command_raw\n";

  return;
}


# -----------------------------------------
# Read exif data.
# - print exif data to file
# - read exif data from file
# - build hash with all tags
# -----------------------------------------
sub read_exifdata {

  my $exiffile         = $appbasename . '.tmp';
  my $ExifTool_command = $EMPTY;

  # exiftool options used:
  # -gpsaltitude#      Extract altitude in raw format
  # -All               Extract all tags
  # −unknown           Extract unknown tags
  # −sort              Sort output alphabetically
  # −dateFormat        Set format for date/time values
  # −coordFormat       Set format for GPS coordinates
  #
  # possible options (currently not used):
  # −short             Print tag names instead of descriptions
  #
  # Resulting output format (example) - with interpretation and formatting:
  # ...
  # Camera Model Name               : COOLPIX AW100
  # Circle Of Confusion             : 0.005 mm
  # GPS Date/Time                   : 2012/08/11-12:16:25
  # GPS Position                    : +53.646810, +7.147873
  # ...
  #
  # Raw output format (example) - without any interpretation or formatting:
  # ...
  # Camera Model Name               : COOLPIX AW100
  # Circle Of Confusion             : 0.00536540368372618
  # GPS Date/Time                   : 2012:08:14 12:25:06Z
  # GPS Position                    : 53.7188333333333 7.34583333333333
  # ...

  my $ExifTool_command_raw = $EMPTY;

  if ( $rawdata ) {
    # Exif data without any interpretation or formatting
    $ExifTool_command_raw = "exiftool -All# -unknown -sort";
  }
  else {
    # Exif data with interpretation and formatting (default)
    $ExifTool_command_raw = "exiftool -gpsaltitude# -All -unknown -sort -dateFormat \"%Y/%m/%d-%H:%M:%S\" -coordFormat \"%+.6f\"";
  }

  if ( $listexif ) {
    # print exif data to stdout
    $ExifTool_command = $ExifTool_command_raw . " \"$sourcefile\"";
  }
  else {
    # print exif data to file
    $ExifTool_command = $ExifTool_command_raw . " \"$sourcefile\" >\"$exiffile\"";
  }

  if ( ( $OSNAME eq 'darwin' ) || ( $OSNAME eq 'linux' ) || ( $OSNAME eq 'freebsd' ) ) {
    # OS X, Linux, FreeBSD
    $command = $ExifTool_command;
    process_command ( $command );
  }
  elsif ( $OSNAME eq 'MSWin32' ) {
    # Windows
    $path    = ".\\windows\\exiftool\\";
    $command = $path . $ExifTool_command;
    process_command ( $command );
  }
  else {
    printf { *STDERR } ( "\nError: Operating system $OSNAME not supported.\n" );
  }

  if ( $listexif ) {
    return
  }

  # read exif data from file
  open ( my $EXIF_FILE, '<', $exiffile ) or die ( "Error opening exiffile \"$exiffile\": $!\n" );

  # clear hash
  %exifdata = ();

  my $key   = $EMPTY;
  my $value = $EMPTY;
  while ( <$EXIF_FILE> ) {
    chomp ();    # no newline
    s/#.*//;     # no comments
    s/^\s+//;    # no leading white
    s/\s+$//;    # no trailing white
    next unless length ();    # anything left?
    ( $key, $value ) = split ( /\s*:\s*/, $_, 2 );
    # collect only the first entry
    if ( ! exists ( $exifdata{ $key } ) ) {
      $exifdata{ $key } = $value;
    }
  }

  close ( $EXIF_FILE );

  # foreach $key ( sort keys %exifdata ) {
  #   print "$key = $exifdata{ $key }\n";
  # }

  return;
}


# -----------------------------------------
# Annotate picture.
# -----------------------------------------
sub annotate_picture {

  my @chunks;
  my $imagetext = $EMPTY;
  my $textchunk = $EMPTY;
  my $exiftag   = $EMPTY;
  my $rest      = $EMPTY;

  @chunks = split ( /{/, $ImageMagick_command );

  foreach my $item ( @chunks ) {
    if ( index ( $item, '}' ) == -1 ) {
      # not found
      $textchunk = $item;
    }
    else {
      # found (split again)
      ( $exiftag, $rest ) = split ( /}/, $item, 2 );
      # lookup in hash
      if ( exists ( $exifdata{ $exiftag } ) ) {

        $textchunk = $exifdata{ $exiftag };
        # escape ' and " as \' and \"
        $textchunk =~ s/([\'\"])/\\$1/g;
        $textchunk = $textchunk . $rest;
      }
      else {
        $textchunk = $rest;
      }
    }
    $imagetext = $imagetext . $textchunk;
  }

  # annotate picture
  if ( ( $OSNAME eq 'darwin' ) || ( $OSNAME eq 'linux' ) || ( $OSNAME eq 'freebsd' ) ) {
    # OS X, Linux, FreeBSD
    $command = $imagetext;
    process_command ( $command );
  }
  elsif ( $OSNAME eq 'MSWin32' ) {
    # Windows
    $path    = ".\\windows\\ImageMagick\\";
    $command = $path . $imagetext;
    process_command ( $command );
  }
  else {
    printf { *STDERR } ( "\nError: Operating system $OSNAME not supported.\n" );
  }

  return;
}


# -----------------------------------------
# Show help and exit.
# -----------------------------------------
sub show_help {

  printf { *STDOUT }
    (   "Copyright (C) 2012-2017 Klaus Tockloth <freizeitkarte\@googlemail.com>\n"
      . "This program comes with ABSOLUTELY NO WARRANTY. This is free software,\n"
      . "and you are welcome to redistribute it under certain conditions.\n\n"
      . "Usage:\n"
      . "perl $programName [-listexif] [-rawdata] [-cfgfile=\"filename\"] [-fileprefix=\"string\"] picture1 ... pictureN\n\n"
      . "Examples:\n"
      . "perl $programName DSCN0200.jpg\n"
      . "perl $programName *.jpg\n"
      . "perl $programName -listexif DSCN0200.jpg\n"
      . "perl $programName -cfgfile=\"label-below.cfg\" DSCN0200.jpg\n"
      . "perl $programName -fileprefix=\"annotated_\" *.jpg\n\n"
      . "Options:\n"
      . "-listexif   = list the readable exif data to stdout\n"
      . "-rawdata    = raw exif data without any interpretation or formatting\n"
      . "-cfgfile    = configuration file (default: $cfgfile)\n"
      . "            = label-above.cfg, label-ontop.cfg, label-below.cfg\n"
      . "-fileprefix = prefix for destination filenames (default: anno_)\n\n"
      . "Arguments:\n"
      . "pictures    = list of pictures to process (wildcards valid)\n\n"
      . "Purpose:\n"
      . "This utility allows it to annotate one or more pictures\n"
      . "with its embedded exif data and or further text.\n\n"
      . "How to use:\n"
      . "1. list the embedded exif data for a sample picture\n"
      . "2. copy and paste one or more exif tags to the config file\n"
      . "3. process your pictures\n\n" );

  exit ( 1 );
}
