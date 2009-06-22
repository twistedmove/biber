package Biber::BibLaTeXML ;
use strict ;
use warnings ;
use Carp ;
use XML::LibXML ;
use Biber::BibLaTeXML::Node ;
use Biber::Utils ;
use Biber::Constants ;
use Data::Dump ;
our @ISA ;


sub _parse_biblatexml {
    my ($self, $xml) = @_ ;
    my $parser = XML::LibXML->new() ;
    my $db ;

    # FIXME : a user _could_ want to encode the bbl in LaTeX!
    $self->{config}->{unicodebbl} = 1 ;


    if ( $xml =~ /\.dbxml$/ ) {
        require Biber::DBXML ;
        push @ISA, 'Biber::DBXML' ;
        print "Querying DBXML  ...\n" unless $self->config('quiet') ;
        my $xmlstring = $self->dbxml_to_xml($xml) ;
        print "Parsing the XML data ...\n" unless $self->config('quiet') ;
        $db = $parser->parse_string( $xmlstring ) 
            or croak "Cannot parse xml string" ;
    } else {
        print "Parsing the XML data ...\n" unless $self->config('quiet') ;
        $db = $parser->parse_file($xml) 
            or croak "Can't parse file $xml" ;
    }

    if ($self->config('validate')) {
        my $xmlschema = XML::LibXML::Schema->new( location => "biblatexml.xsd" ) ;
        
        my $validation = eval { $xmlschema->validate($db) ; } ; 

        unless ($validation) {
            croak "The file $xml does not validate against the BibLaTeXML schema!\n$@"
        } 
    }
    
    # keep track of citekeys that were not found in this database
    my %citekeysnotfound = () ;
    my @auxcitekeys = $self->citekeys ;
    
    if ($self->config('allentries')) {
        @auxcitekeys = () ;
        my $res = $db->findnodes('/*/bib:entry') ;
        foreach my $r ($res->get_nodelist) {
            push @auxcitekeys, $r->findnodes('@id')->string_value
        } ;
    } ;
    
    print "Processing the XML data ...\n" unless $self->config('quiet') ;

    # Contrary to the bibtex approach, we are not extracting all data to
    # the bibentries hash, but only the ones corresponding to @auxcitekeys
    foreach my $citekey (@auxcitekeys) {
        next if $self->{bib}->{$citekey} ; # skip if this is already found in another database
        print "Looking for $citekey\n" if $self->config('debug') ;
        my $xpath = '/*/bib:entry[@id="' . $citekey . '"]' ;
        my $results = $db->findnodes($xpath) ;

        unless ( $results ) {

            carp "Can't find entry with citekey $citekey... skipping"
                 unless $self->config('quiet') ;
            
            $citekeysnotfound{$citekey} = 1 ;
            next
        } ;

        if ( $results->size() > 1 ) { 
            carp "The database contains more than one bib:entry with id=\"$citekey\" !" 
        } ;

        my $bibrecord = $results->get_node(1) ; 

        # if we have an entryset we add the keys to the stack
        if ($bibrecord->findnodes('@entrytype')->string_value eq 'set') {
            
            my @entrysetkeys = split /,/, $bibrecord->findnodes('bib:entryset')->_normalize_string_value ;

            push @auxcitekeys, @entrysetkeys ;

            foreach my $setkey (@entrysetkeys) {
                $Biber::inset_entries{$setkey} = $citekey ;
            }
        }
        # if there is a crossref, we increment its citekey in %crossrefkeys
        elsif ( $bibrecord->exists('bib:crossref') ) {

            my $crefkey = $bibrecord->findnodes('bib:crossref')->_normalize_string_value ;

            $Biber::crossrefkeys{$crefkey}++ ;
            $Biber::entrieswithcrossref{$citekey} = $crefkey ;
        }

    } ;

    # now we add all crossrefs to the stack
    unless ( $self->config('allentries') ) {
        push @auxcitekeys, ( keys %Biber::crossrefkeys ) ;
    } ;
    #--------------------------------------------------

    foreach my $citekey (@auxcitekeys) {
        next if $citekeysnotfound{$citekey} ;
        next if $self->{bib}->{$citekey} ; # skip if this is already found in another database
        print "Processing key $citekey\n" if $self->config('debug') ;
        my $xpath = '/*/bib:entry[@id="' . $citekey . '"]' ;
        my $results = $db->findnodes($xpath) ;
        my $bibrecord = $results->get_node(1) ; 

        $self->{bib}->{$citekey}->{entrytype} = $bibrecord->findnodes('@entrytype')->string_value ;
        if ($bibrecord->exists('@type')) {
            $self->{bib}->{$citekey}->{type} = $bibrecord->findnodes('@type')->string_value ;
        } ;
        $self->{bib}->{$citekey}->{datatype} = 'xml' ;

        #TODO get the options field first 
        #options/text or option: key+value
        if ($bibrecord->exists("bib:options")) {
            if ($bibrecord->findnodes("bib:options/bib:option")) {
                my @opts ; 
                foreach my $o ($bibrecord->findnodes("bib:options/bib:option")->get_nodelist) {
                    my $k = $o->findnodes("bib:key")->_normalize_string_value ; 
                    my $v = $o->findnodes("bib:value")->_normalize_string_value ;
                    push @opts, "$k=$v" ;
                } ;
                $self->{bib}->{$citekey}->{options} = join(",", @opts) ;
            }
            else {
                $self->{bib}->{$citekey}->{options} = $bibrecord->findnodes("bib:options")->_normalize_string_value ;
            }
        } ;
        
        # then we extract in turn the data from each type of fields

        #First we handle the title:
       
        my $titlename = "title" ;
        
        if ( $self->{bib}->{$citekey}->{entrytype} eq 'periodical') {
            if ($bibrecord->exists("bib:journaltitle")) {
                $titlename = 'journaltitle'
            } elsif ($bibrecord->exists("bib:journal")) {
                $titlename = 'journal'
            }
        }

        if ($bibrecord->exists("bib:$titlename") ) {

            # displaymode
            my $titledm = $self->get_displaymode($citekey, $titlename) ;

            my $titlestrings = $bibrecord->_find_biblatex_nodes($self, $titlename, $titledm)->_biblatex_title_values ;

            $self->{bib}->{$citekey}->{$titlename} = $titlestrings->{'title'} ;

            my @specialtitlefields = qw/sorttitle indextitle indexsorttitle/ ;
            foreach my $field (@specialtitlefields) {
                if (! $bibrecord->exists("bib:$field") ) {
                    $self->{bib}->{$citekey}->{$field} = $titlestrings->{$field}
                }
            }
        }

        # then all other literal fields
        foreach my $field (@LITERALFIELDS, @VERBATIMFIELDS) {
            next if $field eq 'title';
            my $dm = $self->get_displaymode($citekey, $field) ;
            $self->{bib}->{$citekey}->{$field} = $bibrecord->_find_biblatex_nodes($self, $field, $dm)->_biblatex_value 
                if $bibrecord->exists("bib:$field") ;
        } 
        
        # list fields
        foreach my $field (@LISTFIELDS) {
            my $dm = $self->get_displaymode($citekey, $field) ;
            my @z ;
            if ($bibrecord->exists("bib:$field")) {
                if ($bibrecord->exists("bib:$field/bib:item")) {
                    foreach my $item ($bibrecord->_find_biblatex_nodes($self, $field, $dm, "item")->get_nodelist) {
                        push @z, $item->_biblatex_value ;
                    }
                }
                else {
                     push @z, $bibrecord->_find_biblatex_nodes($self, $field, $dm)->_biblatex_value
                } ;
                if ($bibrecord->exists("bib:$field\[\@andothers='true'\]")) {
                    push @z, "others"
                } ;
                $self->{bib}->{$citekey}->{$field} = [ @z ]
            }
        } 
        
        # year, origyear
        # TODO support for localyear / origlocalyear and localcalendar
        foreach my $field ( array_minus(\@RANGEFIELDS, [ 'pages' ]) ) {
            if ($bibrecord->exists("bib:$field")) {
                if ($bibrecord->exists("bib:$field/bib:start")) {
                     my $fieldstart = $bibrecord->findnodes("bib:$field/bib:start")->_normalize_string_value ;
                     my $fieldend   = $bibrecord->findnodes("bib:$field/bib:end")->_normalize_string_value ;
                    $self->{bib}->{$citekey}->{$field} = "$fieldstart\\bibrangedash $fieldend" ;
                }
                else {
                    $self->{bib}->{$citekey}->{$field} = 
                        $bibrecord->findnodes("bib:$field/text()")->_normalize_string_value
                }

                if ($bibrecord->exists("bib:$field\[\@type=\"converted\"\]")) {
                    $self->{bib}->{$citekey}->{"local$field"} = 
                        $bibrecord->findnodes("bib:$field/bib:localyear")->_normalize_string_value ;

                    $self->{bib}->{$citekey}->{"local".$field."calendar"} = 
                        $bibrecord->findnodes("bib:$field/bib:localyear/\@calendar")->string_value
                }
            }
        }

        # pages
        if ($bibrecord->exists("bib:pages")) {
            if ($bibrecord->exists("bib:pages/bib:start")) {
                 my $pagesstart = $bibrecord->findnodes("bib:pages/bib:start")->_normalize_string_value ;
                 my $pagesend   = $bibrecord->findnodes("bib:pages/bib:end")->_normalize_string_value ;
                 $self->{bib}->{$citekey}->{pages} = "$pagesstart\\bibrangedash $pagesend" ;
            }
            elsif ($bibrecord->exists("bib:pages/bib:list")) {
                $self->{bib}->{$citekey}->{pages} = 
                    $bibrecord->findnodes("bib:pages/bib:list")->_normalize_string_value
            }
            else {
                $self->{bib}->{$citekey}->{pages} = 
                    $bibrecord->findnodes("bib:pages")->_normalize_string_value
            }
        }

        # the name fields are somewhat more complex ...
        foreach my $field (@NAMEFIELDS) {
            my $dm = $self->get_displaymode($citekey, $field) ;
            if ($bibrecord->exists("bib:$field")) {
                my @z ;
                if ($bibrecord->exists("bib:$field/bib:person")) {
                    foreach my $person ($bibrecord->_find_biblatex_nodes($self, $field, $dm, "person")->get_nodelist) {
                        my $lastname ; 
                        my $firstname ; 
                        my $prefix ; 
                        my $suffix ;
                        my $namestr = "" ;
                        my $nameinitstr = undef ;
                        if ($person->exists('bib:last')) {
                            $lastname = $person->findnodes('bib:last')->_normalize_string_value ;
                            $firstname = $person->findnodes('bib:first')->_normalize_string_value ; 
                            $prefix = $person->findnodes('bib:prefix')->_normalize_string_value 
                                if $person->exists('bib:prefix') ;
                            $suffix = $person->findnodes('bib:suffix')->_normalize_string_value
                                if $person->exists('bib:suffix') ;
                            
                            #FIXME the following code is a repetition of part of parsename() 
                            $namestr .= $prefix if $prefix ;
                            $namestr .= $lastname ;
                            $namestr .= ", " . $firstname if $firstname ;

                            $nameinitstr = "" ;
                            $nameinitstr .= substr( $prefix, 0, 1 ) . "_"
                              if ( $self->getblxoption('useprefix', $citekey) and $prefix ) ;
                            $nameinitstr .= $lastname ;
                            $nameinitstr .= "_" . terseinitials($firstname) 
                                if $firstname ;

                            push @z, 
                                { lastname => $lastname, firstname => $firstname, 
                                  prefix => $prefix, suffix => $suffix,
                                  namestring => $namestr, 
                                  nameinitstring => $nameinitstr }
                        }
                        # Schema allows <person>text<person>
                        else {
                            my $useprefix = $self->getblxoption('useprefix', $citekey) ;

                            push @z, parsename( $person->_normalize_string_value, {useprefix => $useprefix} )
                        }
                    } 
                } 
                # only one name as string, without <person>
                else {
                    my $useprefix = $self->getblxoption('useprefix', $citekey) ;

                    push @z, parsename( $bibrecord->findnodes("bib:$field")->_normalize_string_value, {useprefix => $useprefix} )
                } ;

                if ($bibrecord->exists("bib:$field\[\@andothers='true'\]")) {
                    push @z, { lastname => "others", namestring => "others" }
                } ;
                
                $self->{bib}->{$citekey}->{$field} = [ @z ]
            }
        } ;

        # now we extract the attributes
        my %xmlattributes = ( 
            'bib:pages/@pagination' => 'pagination',
            'bib:pages/@bookpagination' => 'bookpagination',
            'bib:author/@type' => 'authortype',
            'bib:editor/@type' => 'editortype',
            'bib:author/@gender' => 'gender',
            # 'bib:editor/@gender' => 'gender', (ignored for now)
            '@howpublished' => 'howpublished'
            ) ; 
        foreach my $attr (keys %xmlattributes) {
            if ($bibrecord->exists($attr)) {
                $self->{bib}->{$citekey}->{ $xmlattributes{$attr} } 
                    = $bibrecord->findnodes($attr)->string_value ;
            }
        }
    } ;

    # now we keep only citekeys that actually exist in the database
    $self->{citekeys} = [ grep { defined $self->{bib}->{$_} } @auxcitekeys ] ;

    return
}

1 ;

__END__

=pod

=head1 NAME

Biber::BibLaTeXML - parse BibLaTeXML database

=head1 METHODS

=head2 _parse_biblatexml

    Internal method to query and parse a BibLaTeXML database.

=head1 AUTHOR

François Charette, C<< <firmicus at gmx.net> >>

=head1 BUGS

Please report any bugs or feature requests on our sourceforge tracker at
L<https://sourceforge.net/tracker2/?func=browse&group_id=228270>. 

=head1 COPYRIGHT & LICENSE

Copyright 2009 François Charette, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

# vim: set tabstop=4 shiftwidth=4 expandtab: 
