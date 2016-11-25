#!/usr/bin/perl

package CitiesParser;

use HTML::Parser ();

use strict;
use warnings;

use base qw(HTML::Parser);

sub start
{
	my ($self, $tag, $attr, $attrseq, $orig) = @_;

	if (lc($tag) eq "select" && $attr->{"name"} eq "city")
	{
		$self->{"startParse"} = 1;
		$self->{"cities"} = [];
		return;
	}

	if ($self->{"startParse"} && lc($tag) eq "option")
	{
		# format { title => "title", value => "number" }

		return if $attr->{"value"} eq "0";
		
		push(@{$self->{"cities"}}, $attr);
	}
}

sub end
{
	my ($self, $tag) = @_;
	if (lc($tag) eq "select")
	{
		$self->{"startParse"} = undef;
	}
}

sub getCities
{
	my $self = shift;
	return exists($self->{"cities"}) ? $self->{"cities"} : [];
}

1;


package main;

use strict;
use warnings;

use WWW::Mechanize;
use JSON;

use utf8;
binmode(STDOUT,':utf8');

$| = 1;

use constant BASE_URL => "http://www.education.ua";
use constant UNIVERSITIES_URL => "http://www.education.ua/universities/";

my $action = shift || "";
my $file = shift   || "";

my $mech = WWW::Mechanize->new();

sub getCityPages
{
	my $cityId = shift;

	my $firstPageUrl = UNIVERSITIES_URL . "?page=1&desc=1&city=$cityId";

	$mech->get($firstPageUrl);

	my @pages = $mech->find_all_links("url_regex" => qr/universities..page=/);

	my @pageUrls = map { BASE_URL . $_->url() } @pages;

	return \@pageUrls;
}

sub getCityLinks
{
	my $pageUrl = shift;

	$mech->get($pageUrl);

	my @links = $mech->find_all_links("url_regex" => qr/universities\/\d+\/?$/);

	my $sub = sub {
		my $urlObj = shift;
		my ($id) = $urlObj->url() =~ /(\d+)\/?$/;
		return ($id =>
			{ "url" => BASE_URL . $urlObj->url(), "text" => $urlObj->text() }
		);
	};

	my %linkStructs = map { $sub->($_) }  @links; # exclude duplicates
	return [ values(%linkStructs) ];
}

sub getCitiesUniversities
{
	$mech->get(UNIVERSITIES_URL);
	my $content = $mech->content();

	my $citiesParser = CitiesParser->new();
	$citiesParser->parse($content);

	my $cities = $citiesParser->getCities();

	foreach my $city (@$cities)
	{
		print "Handling " . $city->{"title"} . "...\n";

		$city->{"pages"} = [];
		$city->{"links"} = [];

		my $cityId = $city->{"value"};

		$city->{"pages"} = getCityPages($cityId);

		foreach my $pageUrl (@{$city->{"pages"}})
		{
			push(@{$city->{"links"}}, @{ getCityLinks($pageUrl) });
		}
	}

	return $cities;
}

sub saveToFile
{
	my $file = shift;

	my $cities = getCitiesUniversities();

	my $fh;

	open($fh, ">", $file) || die("Could not write to $file: $!");
	print $fh encode_json($cities);
	close($fh);

	print "Done\n";
}

sub showFromFile
{
	my ($file, $handler) = @_;

	my $fh; 
	my $str = "";

	open($fh, "<", $file) || die("Could not read from $file: $!");
	while (<$fh>)
	{
		$str .= $_;
	}
	close($fh);

	my $struct = decode_json($str);
	$handler->($struct);
}

sub showCSV
{
	my $cities = shift;

	print "City,Univercity,Link\n";
	foreach my $city (@$cities)
	{
		next if (! exists($city->{"links"}));
		my $link;
		foreach $link (@{$city->{"links"}})
		{
			print '"' . join('","',
				$city->{"title"},
				$link->{"text"},
				$link->{"url"}
			) . '"' . "\n";	
		}
	}
}

sub main
{
	saveToFile($file) if ($action eq "save");
	showFromFile($file, \&showCSV) if ($action eq "show");	
}

eval { main() };
print "Something wrong: $@\n" if ($@);

1;
