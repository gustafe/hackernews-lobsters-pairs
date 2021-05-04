#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Reddit::Client;
my $version = '1.0';
use Data::Dumper;
my $reddit = new Reddit::Client(
				user_agent => "HNLO agent $version; http://gerikson.com/hnlo; gerikson on Lobste.rs",
				client_id => 'dniT6jXPUH-PrQ',
				secret => 'mLbxHGQqv0aey2h_URTarxW0r8w',
				username => 'gerikson',
				password => '8w7o4MBBQqLA');

my $posts = $reddit->get_links( subreddit=>'programming', limit => 3, view=>'new');

foreach my $post (@{$posts}) {
#       print Dumper $post;
    next if $post->{is_self};
    say join(' ', map { $post->{$_} } qw/id created_utc url title author num_comments score/);
    my $diff = $post->{created} - $post->{created_utc};
    say "Diff: $diff";
}
