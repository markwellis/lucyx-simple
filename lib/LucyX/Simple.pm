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

#use whole bunch of Lucy modules

#indexer modules
use Lucy::Index::Indexer;
use Lucy::Plan::Schema;
use Lucy::Analysis::PolyAnalyzer;
use Lucy::Plan::FullTextType;

use Data::Page;
use Exception::Simple;

#REMOVE ONCE TESTED
use Data::Dumper;
#END REMOVE

has _language => (
    'is' => 'ro',
    'isa' => 'Str',
    'default' => 'en',
    'init_arg' => 'language',
);

has _index_path => (
    'is' => 'ro',
    'isa' => 'Str',
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

has _indexer => (
    'is' => 'ro',
    'init_arg' => undef,
    'lazy_build' => 1,
);

sub _build__indexer{
    my $self = shift;

    my $schema = Lucy::Plan::Schema->new;
   
    my $types = {
        'text' => Lucy::Plan::FullTextType->new(
            'analyzer' => $self->_analyser,
        )
    };

    foreach my $spec ( @{$self->schema} ){
        $spec->{'type'} = $types->{'text'};
        $schema->spec_field( %{$spec} );
    }
    
    # Create the index and add documents.
    return Lucy::Index::Indexer->new(
        schema => $schema,   
        index  => $self->_index_path,
        create => ( -f $self->_index_path . '/schema_1.json' ) ? 0 : 1,
    );
}

has _searcher => (
    'is' => 'ro',
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

sub search{
    my ( $self, $query_string, $page ) = @_;

    Exception::Simple->throw('no query string') if !$query_string;
    $page ||= 1;

    my $query = $self->_query_parser->parse( $query_string );
    my $hits = $self->_searcher->hits(
        'query' => $query,
        'offset' => ( ( $self->entries_per_page * $page) - $self->entries_per_page ),
        'num_wanted' => $self->entries_per_page,
    );
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
    return undef;

}

sub create{
    my ( $self, $document ) = @_;

    Exception::Simple->throw('no document') if ( !$document );

    $self->_indexer->add_doc( $document );
}

sub update_or_create{
}

sub delete{
}

sub commit{
    shift->_indexer->commit;
}

__PACKAGE__->meta->make_immutable;
