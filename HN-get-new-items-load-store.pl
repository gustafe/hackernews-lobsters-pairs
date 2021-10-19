#! /usr/bin/env perl
use Modern::Perl '2015';
###

use JSON;
use HNLOlib qw/get_dbh get_ua $feeds $sql/;
use Data::Dumper;
use Getopt::Long;
use open IO => ':utf8';
use List::Util qw/sum/;
use Template;
use FindBin qw/$Bin/;
use utf8;

#binmode STDOUT, ':utf8';
# read from list

sub usage {
    say "usage: $0 [--help] [--read_back]";
    exit 1;

}
my $read_back = undef;
my $help      = '';
GetOptions( 'read_back' => \$read_back, 'help' => \$help );
usage if $help;

my @failed;
my @items;
my $debug = 0;
my $ua    = get_ua();

my $insert_sql = $feeds->{hn}->{insert_sql};
my $start_sql;
if ($read_back) {
    $start_sql = qq{select min(id) from hackernews};
}
else {
    $start_sql = qq{select max(id) from hackernews};
}

my $dbh = get_dbh();
my $sth;    # = $dbh->prepare( $latest_sql);

my $start_id = ( $dbh->selectall_arrayref($start_sql) )->[0]->[0]
    or die $dbh->errstr;
say "==> start_id: $start_id" if $debug;

my $newest_url  = 'https://hacker-news.firebaseio.com/v0/newstories.json';
my $topview_url = 'https://hacker-news.firebaseio.com/v0/topstories.json';
my $list;
my $response;
my $rem = $start_id % 1_000;
my $delta = 10_000 + $rem;
if ($read_back) {

    $list = [ $start_id - $delta .. $start_id - 1 ];
}
else {
    $response = $ua->get($newest_url);
    if ( !$response->is_success ) {
        die $response->status_line;
    }

    $list = decode_json( $response->decoded_content );
}
my $count = 0;
print "\n";
while ( @{$list} ) {

    my $id = shift @{$list};
    say "reading $id..." if $debug;
    if ( !defined($read_back) and $id <= $start_id ) {
        next;
    }
    my $item_url
        = 'https://hacker-news.firebaseio.com/v0/item/' . $id . '.json';
    my $res = $ua->get($item_url);
    if ( !$res->is_success ) {
        warn $res->status_line;
        warn "--> fetch for $id failed\n";
        push @failed, $id;
        next;
    }
    my $payload = $res->decoded_content;
    if ( $payload eq 'null' ) {
        #say "++> $id has null content" unless $read_back;
        next;
    }
    my $item = decode_json($payload);

    # skip items without URLs
    if ( !defined $item->{url} ) {
        #say "~~> $id has no URL, skipping" unless $read_back;
        next;
    }
    if ( defined $item->{dead} ) {
        #say "**> $id flagged 'dead', skipping" unless $read_back;
        next;
    }
    if ( defined $item->{deleted} ) {
        #say "__> $id flagged 'deleted', skipping" unless $read_back;
        next;
    }


        # let's make a nice line
        my $title = $item->{title} ? $item->{title} : '<NO TITLE>';
        my $title_space = 80 - ($read_back?18:10) - (
            4 + sum(
                map { length( $item->{$_} ? $item->{$_} : 0 ) }
                    qw/by score descendants/
            )
        );
        if ( length($title) > $title_space ) {
            $title = substr( $title, 0, $title_space - 1 ) . "\x{2026}";
        }

    if ($read_back) {
        printf(
            "[%4.1f%%] %d %-*s [%s %d %d]\n",
            ( $delta - ( $start_id - $item->{id} ) ) / $delta * 100,
            $item->{id},
            $title_space,
            $title,
            map { $item->{$_} ? $item->{$_} : 0 } qw/by score descendants/
        ) if sum(map{$item->{$_}?$item->{$_}:0} qw/score descendants/)>=10;
	
    } else {
	# printf(
        #     "%d %-*s [%s %d %d]\n",
	#     $item->{id},
        #     $title_space,
        #     $title,
        #     map { $item->{$_} ? $item->{$_} : 0 } qw/by score descendants/
        # );
	my $hn_link = 'https://news.ycombinator.com/item?id='.$item->{id};
	#	printf("* [%d](%s) [%s](%s) %s %d %d\n",	      $item->{id}, $hn_link,$title,map{$item->{$_}} qw/url by score descendants/);
    }

    push @items,
        [ map { $item->{$_} }
            ( 'id', 'time', 'url', 'title', 'by', 'score', 'descendants' ) ];
    $count++;
}

#add to store
$sth = $dbh->prepare( $feeds->{hn}->{insert_sql} ) or die $dbh->errstr;
foreach my $item (@items) {
    $sth->execute( @{$item} ) or warn $sth->errstr;
}
$sth->finish();
#say "\nNew HN items added: $count\n";
if ( scalar @failed > 0 ) {
    say "### ITEMS NOT FOUND ###";
    foreach my $id (@failed) {
        say $id;
    }
}
my %data = (entries=>\@items);
my $tt = Template->new( {INCLUDE_PATH=>"$Bin/templates",ENCODING=>'UTF-8'} );
$tt->process( 'HN-log.tt', \%data) || die $tt->error;


### update items that are part of sets
unless ($read_back) {

    # $sth = $dbh->prepare( $sql->{get_pairs_10d} );
    # my %sets = %{ HNLOlib::get_all_sets($sth) };
    # my @list;
    # my $days = 7;
    # my $now  = time();
    # foreach my $url ( keys %sets ) {
    #     foreach my $ts ( keys %{ $sets{$url}->{entries} } ) {
    #         my $entries = $sets{$url}->{entries}->{$ts};
    #         if (    $entries->{tag} eq 'hn'
    #             and $entries->{time} >= ( $now - $days * 24 * 3600 ) )
    #         {
    #             push @list, $entries->{id};
    #         }
    #     }
    # }
    # say "items in store in the last $days days: ", scalar @list;
    # HNLOlib::update_from_list( 'hn', \@list );

## grab the current front page
    $response = $ua->get($topview_url);
    if ( !$response->is_success ) {
        die $response->status_line;
    }
    my $top_ids = decode_json( $response->decoded_content );
    $sth
        = $dbh->prepare(
        "insert into hn_frontpage (id, rank, read_time) values (?,?,datetime('now'))"
        ) or die $dbh->errstr;
    my $rank = 1;
    foreach my $id (@$top_ids) {
        next if $rank > 30;    # only first  page
        $sth->execute( $id, $rank ) or warn $sth->errstr;
        $rank++;
    }
}
$dbh->disconnect();

