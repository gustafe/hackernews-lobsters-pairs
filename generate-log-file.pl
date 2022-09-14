#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Template;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use HNLOlib qw/get_dbh $feeds extract_host/;
use utf8;
use File::Find;
use Data::Dump qw/dump/;
use open IO => ':utf8';
#binmode(STDOUT, ":encoding(UTF-8)");
my $logdir = "$Bin/Logs";
#my %sources;
my %data;
my $dbh = get_dbh;
for my $tag (sort keys %$feeds) {
    my $stmt = $feeds->{$tag}->{select_latest_sql};

    my $res = $dbh->selectall_hashref( $stmt, q/created_time/ );

    for my $ct (sort {$b cmp $a} keys %$res) {
	#	dump $res->{$ct};
#	
	my $entry = $res->{$ct};
	next unless defined $entry->{url};
	$entry->{host} = extract_host( $entry->{url});
	push @{$data{sources}{$tag}->{entries}}, $entry;
    }
}
#my $data->{sources} = \%sources;
my $tt = Template->new( {INCLUDE_PATH=>"$Bin/templates",ENCODING=>'UTF-8'} );
$tt->process( 'log.tt', \%data,
    { binmode => ':utf8' }
	    ) || die $tt->error;

__END__
opendir(my $dh, $logdir) || die "can't open $logdir: $!";
my @files = readdir $dh;
exit 0 unless @files; 
my @entries;
my $count = 0;
for my $f (sort{$b cmp $a} @files ) {
    next if ( $f eq '.' or $f eq '..' or $f =~ /\.log$/);
#    say $f;
    next if $count > 23;

    open my $fh, "<:encoding(UTF-8)", "$logdir/$f" or die "can't open $logdir/$f: $!";
    #$contents .= do{ local $/;<$fh>};
    push @entries, {title=>$f, text=>do{local $/; <$fh>}};
    close $fh;
    $count++;
}

my %data = ( entries => \@entries );
my $tt = Template->new( {INCLUDE_PATH=>"$Bin/templates",ENCODING=>'UTF-8'} );
$tt->process( 'log.tt', \%data,
	       '/home/gustaf/public_html/hnlo/log.html',
    { binmode => ':utf8' }
	    ) || die $tt->error;
