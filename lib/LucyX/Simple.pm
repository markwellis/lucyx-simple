package LucyX::Simple;
use strict;
use warnings;

our $VERSION = '0.001';
$VERSION = eval $VERSION;

#use whole bunch of Lucy modules

use Data::Page;

sub new{
    my $invocant = shift;
    my $class = ref( $invocant ) || $invocant;

    my $self = {};
    bless( $self, $class );

#set options here

    return $self;
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
