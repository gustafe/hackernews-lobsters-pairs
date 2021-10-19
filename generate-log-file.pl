#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Template;
use FindBin qw/$Bin/;
use utf8;
use File::Find;
binmode(STDOUT, ":encoding(UTF-8)");
my $logdir = "$Bin/Logs";
opendir(my $dh, $logdir) || die "can't open $logdir: $!";
my @files = readdir $dh;
exit 0 unless @files; 
my @entries;
my $count = 0;
for my $f (sort{$b cmp $a} @files ) {
    next if ( $f eq '.' or $f eq '..' );
    say $f;
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
