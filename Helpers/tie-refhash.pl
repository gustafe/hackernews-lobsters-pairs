#! /usr/bin/env perl
use Modern::Perl '2015';
###
    say '-' x 20;
use Tie::RefHash;
my %h;
    tie %h, 'Tie::RefHash';
    my $a = [];
    my $b = {};
    my $c = \*main;
    my $d = \"gunk";
    my $e = sub { 'foo' };
    %h = ($a => 1, $b => 2, $c => 3, $d => 4, $e => 5);
    $a->[0] = 'foo';
    $b->{foo} = 'bar';
    for (keys %h) {
       print ref($_), "\n";
    }
    tie %h, 'Tie::RefHash::Nestable';
    $h{$a}->{$b} = 1;
    for (keys %h, keys %{$h{$a}}) {
       print ref($_), "\n";
    }
