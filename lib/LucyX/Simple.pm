package LucyX::Simple;
use strict;
use warnings;

our $VERSION = '0.001';
$VERSION = eval $VERSION;

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

sub new{
    my ( $invocant, $args ) = @_;
    my $class = ref( $invocant ) || $invocant;

    my $self = {};
    bless( $self, $class );

    $self->_setup( $args );

    return $self;
}

sub resultclass{
# don't use _mk_accessor coz we need to use the resultclass so we can instanciate the object
    my ( $self, $option ) = @_;

    if ( defined( $option ) ){
        $self->{'resultclass'} = $option;
        eval "use ${option}";
    }

    return $self->{'resultclass'};
}

sub _setup{
    my ( $self, $args ) = @_;
    
    foreach my $option ( qw/index_path schema search_fields language analyser search_boolop entries_per_page/ ){
        $self->_mk_accessor( $option );
    }
    
    foreach my $option ( qw/index_path schema search_fields/ ){
        if ( !defined( $args->{ $option } ) ){
            Exception::Simple->throw("${option} is required");
        } else {
            $self->$option( $args->{ $option } );
        }
    }

    $self->language( $args->{'language'} || 'en');

    $self->analyser( $args->{'analyser'} || Lucy::Analysis::PolyAnalyzer->new( language => $self->{'language'} ) );

    $self->search_boolop( $args->{'search_boolop'} || 'OR' );

    $self->resultclass( $args->{'resultclass'} || 'LucyX::Simple::Result::Object' );

    $self->entries_per_page( $args->{'entries_per_page'} || 100 );
}

sub _mk_accessor{
    my ( $self, $name ) = @_;
    
    my $class = ref( $self ) || $self;
    {
        no strict 'refs';
        *{$class . '::' . $name} = sub {
            my $sub_self = shift; 
            my $option = shift;

            if ( defined( $option ) ){
                $sub_self->{ $name } = $option;
            }

            return $sub_self->{ $name };
        };
    }
}

sub search{
}

sub create{
}

sub update_or_create{
}

sub delete{
}

sub commit{
}

1;
