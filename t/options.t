# -*- cperl -*-
use strict;
use warnings;
use utf8;
no warnings 'utf8' ;

use Test::More tests => 9;

use Biber;
use Biber::Output::bbl;
use Log::Log4perl;
chdir("t/tdata") ;

# Set up Biber object
my $biber = Biber->new(noconf => 1);
my $LEVEL = 'ERROR';
my $l4pconf = qq|
    log4perl.category.main                             = $LEVEL, Screen
    log4perl.category.screen                           = $LEVEL, Screen
    log4perl.appender.Screen                           = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.utf8                      = 1
    log4perl.appender.Screen.Threshold                 = $LEVEL
    log4perl.appender.Screen.stderr                    = 0
    log4perl.appender.Screen.layout                    = Log::Log4perl::Layout::SimpleLayout
|;
Log::Log4perl->init(\$l4pconf);

$biber->parse_ctrlfile('options.bcf');
$biber->set_output_obj(Biber::Output::bbl->new());

# Options - we could set these in the control file but it's nice to see what we're
# relying on here for tests

# Biber options
Biber::Config->setoption('fastsort', 1);
Biber::Config->setoption('sortlocale', 'C');
# Testing customg xsv format sep
Biber::Config->setoption('xsvsep', '\s*\|\s*');

# Biblatex options
Biber::Config->setblxoption('labeldatespec', [ {content => 'date', type => 'field'} ]);

# Now generate the information
$biber->prepare;
my $out = $biber->get_output_obj;
my $section = $biber->sections->get_section(0);
my $main = $biber->sortlists->get_list(0, 'nty', 'entry', 'nty');
my $bibentries = $section->bibentries;

my $dmv =  [
              [
               {'presort'    => {}},
               {'mm'         => {}},
              ],
              [
               {'sortkey'    => {'final' => 1}}
              ],
              [
               {'sortname'   => {}},
               {'author'     => {}},
               {'editor'     => {}},
               {'translator' => {}},
               {'sorttitle'  => {}},
               {'title'      => {}}
              ],
              [
               {'sorttitle'  => {}},
               {'title'      => {}}
              ],
              [
               {'sortyear'   => {}},
               {'year'       => {}}
              ],
              [
               {'volume'     => {}},
               {'0000'       => {}}
              ]
             ];

my $bln = [ {content => 'author'}, {content => 'editor'} ];

my $l1 = q|    \entry{L1}{book}{}
      \name{labelname}{1}{}{%
        {{uniquename=0,hash=bd051a2f7a5f377e3a62581b0e0f8577}{Doe}{D\bibinitperiod}{John}{J\bibinitperiod}{}{}{}{}}%
      }
      \name{author}{1}{}{%
        {{uniquename=0,hash=bd051a2f7a5f377e3a62581b0e0f8577}{Doe}{D\bibinitperiod}{John}{J\bibinitperiod}{}{}{}{}}%
      }
      \list{publisher}{1}{%
        {Oxford}%
      }
      \strng{namehash}{bd051a2f7a5f377e3a62581b0e0f8577}
      \strng{fullhash}{bd051a2f7a5f377e3a62581b0e0f8577}
      \field{sortinit}{D}
      \field{sortinithash}{a01c54d1737685bc6dbf0ea0673fa44c}
      \field{labelyear}{1998}
      \field{labelmonth}{04}
      \field{labelday}{05}
      \field{datelabelsource}{}
      \field{labeltitle}{Title 1}
      \field{day}{05}
      \field{month}{04}
      \field{origday}{30}
      \field{origmonth}{10}
      \field{origyear}{1985}
      \field{title}{Title 1}
      \field{year}{1998}
      \keyw{one,two,three}
    \endentry
|;

my $l2 = q|    \entry{L2}{book}{maxcitenames=3,maxbibnames=3,maxitems=2}
      \name{labelname}{1}{}{%
        {{uniquename=0,hash=19eec87c959944d6d9c72434a42856ba}{Edwards}{E\bibinitperiod}{Ellison}{E\bibinitperiod}{}{}{}{}}%
      }
      \name{author}{1}{}{%
        {{uniquename=0,hash=19eec87c959944d6d9c72434a42856ba}{Edwards}{E\bibinitperiod}{Ellison}{E\bibinitperiod}{}{}{}{}}%
      }
      \list{publisher}{1}{%
        {Oxford}%
      }
      \strng{namehash}{19eec87c959944d6d9c72434a42856ba}
      \strng{fullhash}{19eec87c959944d6d9c72434a42856ba}
      \field{sortinit}{E}
      \field{sortinithash}{655e26c7438ff123e5c69c6c3f702107}
      \field{labelyear}{1998}
      \field{labelmonth}{04}
      \field{labelday}{05}
      \field{datelabelsource}{}
      \field{labeltitle}{Title 2}
      \field{day}{05}
      \field{month}{04}
      \field{title}{Title 2}
      \field{year}{1998}
    \endentry
|;

my $l3 = q|    \entry{L3}{book}{blah=10}
      \name{labelname}{1}{}{%
        {{uniquename=0,hash=490250da1f3b92580d97563dc96c6c84}{Bluntford}{B\bibinitperiod}{Bunty}{B\bibinitperiod}{}{}{}{}}%
      }
      \name{author}{1}{}{%
        {{uniquename=0,hash=490250da1f3b92580d97563dc96c6c84}{Bluntford}{B\bibinitperiod}{Bunty}{B\bibinitperiod}{}{}{}{}}%
      }
      \list{publisher}{1}{%
        {Oxford}%
      }
      \strng{namehash}{490250da1f3b92580d97563dc96c6c84}
      \strng{fullhash}{490250da1f3b92580d97563dc96c6c84}
      \field{sortinit}{B}
      \field{sortinithash}{1a3a21dbed09540af12d49a0b14f4751}
      \field{labelyear}{1999}
      \field{labelmonth}{04}
      \field{labelday}{05}
      \field{datelabelsource}{}
      \field{labeltitle}{Title 3}
      \field{day}{05}
      \field{month}{04}
      \field{title}{Title 3}
      \field{year}{1999}
    \endentry
|;

ok(Biber::Config->getblxoption('uniquename') == 1, "Single-valued option") ;
is_deeply(Biber::Config->getblxoption('labelnamespec'), [ {content => 'author'} ], "Multi-valued options");
ok(Biber::Config->getoption('mincrossrefs') == 88, "Setting Biber options via control file");
ok(Biber::Config->getblxoption('useprefix', 'book') == 1 , "Per-type single-valued options");
is_deeply(Biber::Config->getblxoption('labelnamespec', 'book'), $bln, "Per-type multi-valued options");
is($bibentries->entry('L1')->get_labeldate_info->{field}{year}, 'year', 'Global labelyear setting' ) ;
is( $out->get_output_entry('L1', $main), $l1, 'Global labelyear setting - labelyear should be YEAR') ;
is( $out->get_output_entry('L2', $main), $l2, 'Entry-local biblatex option mappings - 1') ;
is( $out->get_output_entry('L3', $main), $l3, 'Entry-local biblatex option mappings - 2') ;
