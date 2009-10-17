package Pod::Elemental::Transformer::Pod5;
use Moose;
with 'Pod::Elemental::Transformer';
# ABSTRACT: the default, minimal semantics of Perl5's pod element hierarchy

use Moose::Autobox 0.10;

use namespace::autoclean;

use Pod::Elemental::Document;
use Pod::Elemental::Element::Pod5::Data;
use Pod::Elemental::Element::Pod5::Ordinary;
use Pod::Elemental::Element::Pod5::Verbatim;
use Pod::Elemental::Element::Pod5::Region;

# TODO: handle the stupid verbatim-correction when inside non-colon-begin

sub _gen_class { "Pod::Elemental::Element::Generic::$_[1]" }
sub _class     { "Pod::Elemental::Element::Pod5::$_[1]" }

sub _collect_regions {
  my ($self, $in_paras) = @_;

  my @in_paras  = @$in_paras; # copy so we do not muck with input doc
  my @out_paras;

  PARA: while (my $para = shift @in_paras) {
    @out_paras->push($para), next PARA
      unless $para->does('Pod::Elemental::Command')
      and    $para->command eq 'begin';

    my ($colon, $target, $content) = $para->content =~ m/
      \A
      (:)?
      (\S+)
      (?:\s+(.+))?
      \Z
    /xs;

    Carp::confess("=begin cannot be parsed") unless defined $target;
    $colon ||= "";

    my @region_paras;
    REGION_PARA: while (my $region_para = shift @in_paras) {
      last REGION_PARA
        if  $region_para->does('Pod::Elemental::Command')
        and ($region_para->command eq 'end')
        and ($region_para->content =~ /^\Q$colon$target\E/);

      Carp::confess("=begin $colon$target region was never terminated")
        unless @in_paras;

      @region_paras->push($region_para);
    };

    my $region = $self->_class('Region')->new({
      children    => $self->_collect_regions(\@region_paras),
      format_name => $target,
      is_pod      => $colon ? 1 : 0,
      content     => defined $content ? $content : '',
    });

    @out_paras->push($region);
  }

  return \@out_paras;
}

sub _strip_ends {
  my ($self, $in_paras) = @_;

  my @in_paras  = @$in_paras; # copy so we do not muck with input doc

  @in_paras->shift
    while $in_paras[0]->does('Pod::Elemental::Command')
    and   $in_paras[0]->command eq 'pod';

  @in_paras->shift
    while $in_paras[0]->isa('Pod::Elemental::Element::Generic::Blank');

  @in_paras->pop
    while $in_paras[-1]->does('Pod::Elemental::Command')
    and   $in_paras[-1]->command eq 'cut';

  @in_paras->pop
    while $in_paras[-1]->isa('Pod::Elemental::Element::Generic::Blank');

  return \@in_paras;
}

sub transform_document {
  my ($self, $document) = @_;

  my $end_stripped     = $self->_strip_ends($document->children);
  my $region_collected = $self->_collect_regions($end_stripped);

  my $new_doc = Pod::Elemental::Document->new({
    children => $region_collected,
  });

  return $new_doc;
}

sub _xform_text {
  my ($self, $para, $stack) = @_;

  my $in_data = $stack->[0]->does('Pod::Elemental::FormatRegion')
             && ! $stack->[0]->is_pod;

  my $new_class = $in_data                   ? $self->_class('Data')
                : ($para->content =~ /\A\s/) ? $self->_class('Verbatim')
                :                              $self->_class('Ordinary');
  
  return $new_class->new({
    content    => $para->content,
    start_line => $para->start_line,
  });
}

1;
