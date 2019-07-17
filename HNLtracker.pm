package HNLtracker;

use strict;
use Exporter;
#use Digest::SHA qw/hmac_sha256_hex/;
use Config::Simple;
use DBI;
use LWP::UserAgent;

use vars qw/$VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS/;

$VERSION = 1.00;
@ISA = qw/Exporter/;
@EXPORT = ();
@EXPORT_OK = qw/get_dbh get_ua/;
%EXPORT_TAGS = (DEFAULT => [qw/&get_dbh &get_ua/]);

my $cfg = Config::Simple->new('/home/gustaf/prj/HN-Lobsters-Tracker/hnltracker.ini');

#### DBH

my $driver = $cfg->param('DB.driver');
my $database = $cfg->param('DB.database');
my $dbuser = $cfg->param('DB.user');
my $dbpass = $cfg->param('DB.password');

sub get_dbh { 
    my $dsn = "DBI:$driver:dbname=$database";
    my $dbh=DBI->connect($dsn, $dbuser, $dbpass, {PrintError=>0}) or die $DBI::errstr;
    return $dbh;
}
#### User agent
sub get_ua {
    my $ua = LWP::UserAgent->new;
    return $ua;
}

1;
