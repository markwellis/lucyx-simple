package LucyX::Simple;

our $VERSION = '0.001';
$VERSION = eval $VERSION;

use Moose;
use namespace::autoclean;

use Moose::Util::TypeConstraints;

subtype 'LoadClass' 
    => as 'ClassName';

coerce 'LoadClass' 
    => from 'Str'
    => via { Class::MOP::load_class($_); $_ };

no Moose::Util::TypeConstraints;

use Lucy::Analysis::PolyAnalyzer;
use Lucy::Plan::Schema;
use Lucy::Index::Indexer;
use Lucy::Search::IndexSearcher;
use Lucy::Search::QueryParser;
use Lucy::Plan::FullTextType;
use Lucy::Plan::BlobType;
use Lucy::Plan::Float32Type;
use Lucy::Plan::Float64Type;
use Lucy::Plan::Int32Type;
use Lucy::Plan::Int64Type;
use Lucy::Plan::StringType;

use Data::Page;
use Exception::Simple;

has _language => (
    'is' => 'ro',
    'isa' => 'Str',
    'default' => 'en',
    'init_arg' => 'language',
);

has _index_path => (
    'is' => 'ro',
    'required' => 1,
    'init_arg' => 'index_path',
);

has _analyser => (
    'is' => 'ro',
    'init_arg' => undef,
    'default' => sub { return Lucy::Analysis::PolyAnalyzer->new( language => shift->_language ) },
    'lazy' => 1,
);

has schema => (
    'is' => 'ro',
    'isa' => 'ArrayRef[HashRef]',
    'required' => 1,
);

has '_index_schema' => (
    'is' => 'ro',
    'isa' => 'Lucy::Plan::Schema',
    'init_arg' => undef,
    'lazy_build' => 1,
);

sub _build__index_schema{
    my $self = shift;
    
    my $schema = Lucy::Plan::Schema->new;

    my $types = {
        'fulltext' => 'Lucy::Plan::FullTextType',
        'blob' => 'Lucy::Plan::BlobType',
        'float32' => 'Lucy::Plan::Float32Type', 
        'float64' => 'Lucy::Plan::Float64Type',
        'int32' => 'Lucy::Plan::Int32Type',
        'int64' => 'Lucy::Plan::Int64Type',
        'string' => 'Lucy::Plan::StringType',
    };

    foreach my $field ( @{$self->schema} ){
        my $type_options = {};
        foreach my $option ( qw/boost indexed stored sortable/ ){
            my $field_option = delete( $field->{ $option } );
            if ( defined( $field_option ) ){
                $type_options->{ $option } = $field_option;
            }
        }

        my $type = $field->{'type'} || 'fulltext';
        if ( $type eq 'fulltext' ){
            $type_options->{'analyzer'} = $self->_analyser;
            $type_options->{'highlightable'} = delete $field->{'highlightable'} || 0;
        }
        $field->{'type'} = $types->{ $type }->new( %{$type_options} );
        $schema->spec_field( %{$field} );
    }
    return $schema;
}

has _indexer => (
    'is' => 'ro',
    'isa' => 'Lucy::Index::Indexer',
    'init_arg' => undef,
    'lazy_build' => 1,
);

sub _build__indexer{
    my $self = shift;

    return Lucy::Index::Indexer->new(
        schema => $self->_index_schema,   
        index  => $self->_index_path,
        create => ( -f $self->_index_path . '/schema_1.json' ) ? 0 : 1,
    );
}

has _searcher => (
    'is' => 'ro',
    'isa' => 'Lucy::Search::IndexSearcher',
    'init_arg' => undef,
    'lazy_build' => 1,
);

sub _build__searcher{
    return Lucy::Search::IndexSearcher->new( 
        'index' => shift->_index_path,
    );
}

has search_fields => (
    'is' => 'ro',
    'isa' => 'ArrayRef[Str]',
    'required' => 1,
);

has search_boolop => (
    'is' => 'ro',
    'isa' => 'Str',
    'default' => 'OR',
);

has _query_parser => (
    'is' => 'ro',
    'isa' => 'Lucy::Search::QueryParser',
    'init_arg' => undef,
    'lazy_build' => 1,
);

sub _build__query_parser{
    my $self = shift;

    my $query_parser = Lucy::Search::QueryParser->new(
        schema => $self->_searcher->get_schema,
        analyzer => $self->_analyser,
        fields => $self->search_fields,
        default_boolop => $self->search_boolop,
    );

    $query_parser->set_heed_colons(1);

    return $query_parser;
}

has resultclass => (
    'is' => 'rw',
    'isa' => 'LoadClass',
    'coerce' => 1,
    'lazy' => 1,
    'default' => 'LucyX::Simple::Result::Object',
);

has entries_per_page => (
    'is' => 'rw',
    'isa' => 'Num',
    'lazy' => 1,
    'default' => 100,
);

sub sorted_search{
    my ( $self, $query, $criteria, $page ) = @_;

    my @rules;
    foreach my $key ( keys( %{$criteria} ) ){
        push( 
            @rules,  
            Lucy::Search::SortRule->new(
                field   => $key,
                reverse => $criteria->{ $key },
            )
        );
    }

    return $self->search( $query, $page, Lucy::Search::SortSpec->new( rules => \@rules ) );
}

sub search{
    my ( $self, $query_string, $page, $sort_spec ) = @_;

    Exception::Simple->throw('no query string') if !$query_string;
    $page ||= 1;

    my $query = $self->_query_parser->parse( $query_string );

    my $search_options = {
        'query' => $query,
        'offset' => ( ( $self->entries_per_page * $page ) - $self->entries_per_page ),
        'num_wanted' => $self->entries_per_page,
    };
    $search_options->{'sort_spec'} = $sort_spec if $sort_spec;

    my $hits = $self->_searcher->hits( %{$search_options} );
    my $pager = Data::Page->new($hits->total_hits, $self->entries_per_page, $page);

    my @results;
    while ( my $hit = $hits->next ) {
        my $result = {};
        foreach my $field ( @{$self->schema} ){
            $result->{ $field->{'name'} } = $hit->{ $field->{'name'} };
        }
        push( @results, $self->resultclass->new( $result ) );
    }

    return ( \@results, $pager ) if scalar(@results);
    Exception::Simple->throw('no results');

}

sub create{
    my ( $self, $document ) = @_;

    Exception::Simple->throw('no document') if ( !$document );

    $self->_indexer->add_doc( $document );
}

sub update_or_create{
    my ( $self, $document, $pk ) = @_;

    Exception::Simple->throw('no document') if !$document;
    $pk ||= 'id';
    my $pv = $document->{ $pk };

    Exception::Simple->throw('no primary key value') if !$pv;
    $self->delete( $pk, $pv );

    $self->create( $document );
}

sub delete{
    my ( $self, $key, $value ) = @_;

    Exception::Simple->throw( 'missing key' ) if !defined( $key );
    Exception::Simple->throw( 'missing value' ) if !defined( $value );

    #delete only works on finished indexes
    $self->commit;
    $self->_indexer->delete_by_term(
        'field' => $key,
        'term' => $value,
    );
}

sub commit{
    my ( $self, $optimise ) = @_;

    $self->_indexer->optimize if $optimise;
    $self->_indexer->commit;

    $self->_clear_indexer;
    $self->_clear_searcher;
}

__PACKAGE__->meta->make_immutable;

=head1 NAME

LucyX::Simple - Simple L<Lucy> Interface

=head1 SYNOPSIS

    use LucyX::Simple;

    my $searcher = LucyX::Simple->new(
        'index_path' => '/tmp/search_index',
        'schema' => [
            {
                'name' => 'title',
                'boost' => 3,
            },{
                'name' => 'description',
            },{
                'name' => 'id',
                'type' => 'string', #you don't want the analyser to adjust your id do you?
            },
        ],
        'search_fields' => ['title', 'description'],
        'search_boolop' => 'AND',
    );

    $searcher->create({
        'id' => 1,
        'title' => 'fibble',
        'description' => 'wibble',
    });

    #important - always commit after updating the index!
    $searcher->commit;

    my ( $results, $pager ) = $searcher->search( 'fibble' );

=head1 DESCRIPTION

Simple interface to L<Lucy>. Use if you want to use L<Lucy> and are lazy, but need more than L<Lucy::Simple> provides :p

=head1 METHODS

=head2 new ( {hashref} )

    #required args
    index_path => path to directory to use as index

    #optional args
    language => language for polyanalyser to use

=head2 B<search>( $query_string, $page ) - search index

    my ( $results, $pager ) = $searcher->search( $query, $page );

=head2 B<create>( $document ) - add item to index

    $searcher->create({
        'id' => 1,
        'title' => 'this is the title',
        'description' => 'this is the description',
    });

not that it has to be, but its highly recommended that I<id> is a unique identifier for this document 

or you'll have to pass $pk to update_or_create

=head2 B<update_or_create>( $document, $pk ) - updates or creates document in the index

    $searcher->update_or_create({
        'id' => 1,
        'title' => 'this is the updated title',
        'description' => 'this is the description',
    }, 'id');

$pk is the unique key to lookup by, defaults to 'id'

=head2 B<delete>( $key, $value ) - remove document from the index

    $searcher->delete( 'id', 1 );

finds $key with $value and removes from index

=head2 B<commit>() - commits and optionaly optimises index after adding documents

    $searcher->commit();

    #or to optimise as well
    $searcher->commit(1);

you must call this after you have finished doing things to the index

=head1 ADVANCED

when creating the Lucy::Simple object you can specify some advanced options

=head2 language

set's language for default _analyser of L<Lucy::Analysis::PolyAnalyzer>

=head2 _analyser

set analyser, defualts to L<Lucy::Analysis::PolyAnalyzer>

=head2 search_fields

fields to search by default, takes an arrayref

=head2 search_boolop

can be I<OR> or I<AND>

search boolop, defaults to or. e.g the following query

    "this is search query"

becomes

    "this OR is OR search OR query"

can be changed to I<AND>, in which case the above becomes

    "this AND is AND search AND query"

=head2 resultclass

resultclass for results, defaults to L<LucyX::Simple::Result::Object> which creates acessors for each key => value returned

could be changed to LucyX::Simple::Result::Hash for a plain old, hashref or a custom class

=head2 entries_per_page

default is 100

=head1 SUPPORT

Bugs should always be submitted via the CPAN bug tracker

For other issues, contact the maintainer

=head1 AUTHORS

n0body E<lt>n0body@thisaintnews.comE<gt>

=head1 SEE ALSO

L<http://thisaintnews.com>, L<Lucy>, L<Exception::Simple>

=head1 LICENSE

Copyright (C) 2012 by n0body L<http://thisaintnews.com/>

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
