#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
use JSON;
use HNLOlib qw/get_dbh get_ua $feeds  $ua get_all_sets  update_scores/;
use IO::Handle;
STDOUT->autoflush(1);
use open qw/ :std :encoding(utf8) /;
use Data::Dumper;
my $sql = {
    all_items =>
qq/select id, title, score, comments,tags from lobsters where created_time >=?  
and created_time<?/,
    update_item =>
      qq/update lobsters set title=?, score=?, comments=? tags=? where id = ?/,
    delete_item => qq/delete from lobsters where id = ?/,
};
my $dbh = get_dbh();
$dbh->{sqlite_unicode} = 1;

sub usage;
sub read_item;
my $target_day;
my $delete_id;
my $debug;
GetOptions( 'target_day=i' => \$target_day, 'delete_id=i' => \$delete_id );
if ( !defined $target_day and !defined $delete_id ) {
    usage;
}
if ($delete_id) {
    my $sth = $dbh->prepare( $sql->{delete_item} ) or die $dbh->errstr;
    my $rv  = $sth->execute($delete_id)            or warn $sth->errstr;
    $sth->finish;
    exit 0;
}
else {

    my ( $year, $month, $day ) = $target_day =~ m/(\d{4})(\d{2})(\d{2})/;
    usage unless ( $month >= 1 and $month <= 12 );

    my $from_dt = DateTime->new(
        year   => $year,
        month  => $month,
        day    => $day,
        hour   => 0,
        minute => 0,
        second => 0
    );
    my $to_dt = DateTime->new(
        year   => $year,
        month  => $month,
        day    => $day,
        hour   => 0,
        minute => 0,
        second => 0
    )->add( days => 1 );

    say "$from_dt -- $to_dt";

    my $sth = $dbh->prepare( $sql->{all_items} ) or die $dbh->errstr;
    my @update_list;
    my @failed;
    my @not_read;
    my @to_delete;
    my @items;
    $sth->execute( $from_dt->ymd, $to_dt->ymd );
    my $ids;
    while ( my $r = $sth->fetchrow_hashref ) {
	push @{$ids->{sequence}},
	  { tag =>'lo',
	    map { $_, $r->{$_}} qw/id title score comments tags/ };
    }

    $sth->finish;
    my @result= @{update_scores($dbh, [$ids])};

}

sub usage {
    say "usage: $0 [--delete_id=ID] --target_day=YYYYMMDD";
    exit 1;
}

