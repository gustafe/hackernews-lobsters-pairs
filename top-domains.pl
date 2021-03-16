#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Getopt::Long;
use List::Util qw/sum/;
use POSIX qw/ceil/;
use URI;
use HNLOlib qw/$feeds get_ua get_dbh get_reddit get_web_items/;

sub usage {
    say "usage: $0 --label={hn,lo,pr}";
    exit 1;

}

sub average {
    sum(@_) / @_;
}

sub median {
    sum( ( sort { $a <=> $b } @_ )[ int( $#_ / 2 ), ceil( $#_ / 2 ) ] ) / 2;
}

my %genre_labels = (
    U => 'unknown',
    G => 'general',
    N => 'news',
    D => 'development'
);

my %domain_genres;

while (<DATA>) {
    chomp;
    my ( $domain, $genre ) = split(/\s+/, $_);
    $domain_genres{$domain} = $genre;

}

my $label;
GetOptions( 'label=s' => \$label );
usage unless exists $feeds->{$label};
my $dbh = get_dbh();
my $statement
    = "select url, score from "
    . $feeds->{$label}->{table_name}
    . " where url!=''";
my $list = $dbh->selectall_arrayref($statement);
$statement = "select date(min(created_time)), date(max(created_time)) from "
    . $feeds->{$label}->{table_name};
my $dates = $dbh->selectall_arrayref($statement);

my $min_ts = $dates->[0]->[0];
my $max_ts = $dates->[0]->[1];

my %data;
my $total = 0;
foreach my $item ( @{$list} ) {
    my $uri   = URI->new( $item->[0] );
    my $score = $item->[1];
    my $host;
    eval {
        $host = $uri->host;
        1;
    } or do {
        my $error = $@;

        #	  say $item->[0];
        $host = 'www';
    };
    $host =~ s/^www\.//;
    $data{$host}->{count}++;
    push @{ $data{$host}->{scores} }, $score;
    $total++;

}
my $limit = 100;

#say " Top $limit domains from $feeds->{$label}->{site} from $min_ts to $max_ts";
#say " Total entries: $total";
say "#Top $limit domains from $feeds->{$label}->{site}";
say join( ',', "#Date range", $min_ts, $max_ts );
say join( ',', "#Total entries", $total );

#say join(",", ("#Top $limit domains from $feeds->{$label}->{site}","#Dates: $min_ts to $max_ts","#Total entries", $total));
say join( ',', qw/Rank Domain Type Count Average Median/ );
my $rank = 1;
foreach my $host (
    sort {
               $data{$b}->{count} <=> $data{$a}->{count}
            || @{ $data{$b}->{scores} } <=> @{ $data{$a}->{scores} }
            || $data{$a} cmp $data{$b}
    } keys %data
    )
{
    next if $rank > $limit;
    say join(
        ",",
        (   $rank,
            $host,
            $domain_genres{$host} ? $genre_labels{$domain_genres{$host}} : 'X',
            $data{$host}->{count},
            sprintf( "%.1f", average( @{ $data{$host}->{scores} } ) ),
            median( @{ $data{$host}->{scores} } )
        )
    );

    $rank++;
}

__DATA__
7pace.com U
9to5mac.com D
aeon.co N
agentanakinai.wordpress.com U
aiprobook.com D
aist.global U
anandtech.com G
android-developers.googleblog.com D
apievangelist.com D
apnews.com N
apps.apple.com G
arp242.net D
arstechnica.com N
artiba.org N
arxiv.org G
aster.cloud U
atlasobscura.com G
aws.amazon.com G
axios.com N
bbc.co.uk N
bbc.com N
beepb00p.xyz D
bfilipek.com U
bleepingcomputer.com D
blog.acolyer.org U
blog.adacore.com D
blog.cloudflare.com D
blog.frankel.ch D
blog.golang.org D
blog.jetbrains.com D
blog.jonlu.ca U
blog.metaobject.com D
blog.mozilla.org D
blog.netbsd.org D
blog.pragmaticengineer.com D
blog.regehr.org D
blog.rust-lang.org D
blog.softwaremill.com D
blog.soshace.com D
blog.trailofbits.com D
blogs.gnome.org D
blogs.scientificamerican.com N
bloomberg.com N
businessinsider.com N
buttondown.email D
buzzfeednews.com N
cacm.acm.org D
calltutors.com U
capitalandgrowth.org U
cbc.ca N
christianfindlay.com D
christine.website D
citylab.com G
cnbc.com N
cnet.com N
cnn.com N
code.visualstudio.com D
coderrocketfuel.com D
codersera.com D
codespot.org D
codesquery.com D
codinginfinite.com D
collabora.com D
css-tricks.com D
ctrl.blog D
cypressoft.com D
daniel.haxx.se D
danluu.com D
data-flair.training D
dataengineeringpodcast.com D
decipherzone.com D
decrypt.co G
dev.to D
devblogs.microsoft.com D
developer.apple.com D
developer.okta.com D
developers.redhat.com D
devever.net D
devmates.co D
dl.acm.org D
dlang.org D
docs.google.com G
docs.keydb.dev D
drewdevault.com D
driftingruby.com D
drive.google.com G
dzone.com D
economist.com N
edition.cnn.com N
eff.org G
eli.thegreenplace.net U
en.wikipedia.org G
engadget.com N
fabiensanglard.net D
fastcompany.com N
fasterthanli.me D
fedoramagazine.org D
finance.yahoo.com G
flak.tedunangst.com D
fluentcpp.com D
forbes.com N
forms.gle U
freecodecamp.org D
ft.com N
functional.christmas D
functionize.com D
fusionauth.io D
geshan.com.np D
gist.github.com D
git.sr.ht D
github.blog D
github.com D
gitlab.com D
gizmodo.com N
google.com G
googleprojectzero.blogspot.com D
groups.google.com G
guix.gnu.org D
habr.com U
hackaday.com D
hackernoon.com D
hacks.mozilla.org D
hanselman.com D
hbr.org N
heartbeat.fritz.ai D
hillelwayne.com D
i-programmer.info D
iafrikan.com U
icyphox.sh D
ideasverge.com U
iism.org G
increment.com U
independent.co.uk N
infoq.com U
innoq.com U
interrupt.memfault.com D
javiercasas.com U
johndcook.com D
jonlennartaasenden.wordpress.com D
jpmens.net D
jvns.ca D
jvt.me D
kdab.com D
kevq.uk D
latimes.com N
learnworthy.net D
leimao.github.io D
lemire.me D
lethain.com U
letterstoanewdeveloper.com D
link.medium.com G
linkedin.com G
lists.freebsd.org D
lists.gnu.org D
luminousmen.com U
lwn.net D
m.youtube.com G
macrumors.com D
mail-index.netbsd.org D
maintainable.fm D
marc.info D
marketwatch.com N
mathematicalramblings.blogspot.com D
matklad.github.io D
medium.com G
meta.stackexchange.com D
metaredux.com D
microsoft.com D
milapneupane.com.np D
mjg59.dreamwidth.org D
mobile.twitter.com G
mooreds.com D
nature.com N
nautil.us D
nbcnews.com N
ncbi.nlm.nih.gov G
news.mit.edu N
news.ycombinator.com G
newscientist.com N
newyorker.com N
nextplatform.com G
notes.eatonphil.com D
npr.org N
nuadox.com D
nullprogram.com D
nytimes.com N
nyxt.atlas.engineer D
oilshell.org D
old.reddit.com G
omgubuntu.co.uk D
onezero.medium.com D
onlineitguru.com D
open.spotify.com D
opensource.com D
openwall.com D
orbifold.xyz D
os2museum.com D
pastebin.com G
petecorey.com U
phoronix.com D
phys.org N
piechowski.io U
pingcap.com D
pixelstech.net D
play.google.com G
pointieststick.com U
politico.com N
pradeeploganathan.com U
prathamesh.tech D
pythonpodcast.com D
pythonspeed.com D
quantamagazine.org N
queue.acm.org N
quora.com G
quuxplusone.github.io D
qvault.io U
qz.com G
rachelbythebay.com D
randomascii.wordpress.com D
raymii.org D
react.christmas D
recruitedby.tech D
reddit.com G
reuters.com N
righto.com D
rubikscode.net D
science.sciencemag.org N
sciencedaily.com N
sciencemag.org N
scientificamerican.com N
scmp.com U
semiengineering.com D
skerritt.blog U
slate.com N
smithsonianmag.com N
soatok.blog D
sobolevn.me U
sourcesort.com D
spectrum.ieee.org N
spin.atomicobject.com U
stackoverflow.blog D
stackoverflow.com D
start.jcolemorrison.com U
stitcher.io D
talospace.com D
taniarascia.com D
techcrunch.com N
technologyreview.com N
technostacks.com N
theatlantic.com N
theconversation.com N
thedrive.com G
theguardian.com N
thenextweb.com N
theregister.co.uk N
theregister.com N
theverge.com N
thomasvilhena.com U
tiny-giant-books.com U
tomshardware.com N
towardsdatascience.com D
toxicpvp.club U
transposit.com U
twitch.tv G
twitter.com G
ubuntu.com D
undeadly.org D
usenix.org D
utcc.utoronto.ca D
v.redd.it G
venturebeat.com N
vermaden.wordpress.com D
ververica.com U
vice.com N
victorzhou.com U
virtuallyfun.com D
vmcall.blog D
vox.com N
washingtonpost.com N
web.archive.org G
wired.com N
wsj.com N
youtu.be G
youtube.com G
zdnet.com N
