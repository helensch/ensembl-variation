
# Ensembl module for Bio::EnsEMBL::Variation::DBSQL::VariationFeatureAdaptor
#
# Copyright (c) 2004 Ensembl
#
# You may distribute this module under the same terms as perl itself
#
#

=head1 NAME

Bio::EnsEMBL::Variation::DBSQL::VariationFeatureAdaptor

=head1 SYNOPSIS

  $vdb = Bio::EnsEMBL::Variation::DBSQL::DBAdaptor->new(...);
  $db  = Bio::EnsEMBL::DBSQL::DBAdaptor->new(...);

  # tell the variation database where core database information can be
  # be found
  $vdb->dnadb($db);

  $va = $vdb->get_VariationAdaptor();
  $vfa = $vdb->get_VariationFeatureAdaptor();
  $sa  = $db->get_SliceAdaptor();

  # Get a VariationFeature by its internal identifier
  $vf = $va->fetch_by_dbID(145);

  # get all VariationFeatures in a region
  $slice = $sa->fetch_by_region('chromosome', 'X', 1e6, 2e6);
  foreach $vf (@{$vfa->fetch_all_by_Slice($slice)}) {
    print $vf->start(), '-', $vf->end(), ' ', $vf->allele_string(), "\n";
  }


  # fetch all genome hits for a particular variation
  $v = $va->fetch_by_name('rs56');

  foreach $vf (@{$vfa->fetch_all_by_Variation($v)}) {
    print $vf->seq_region_name(), $vf->seq_region_start(), '-',
          $vf->seq_region_end(),"\n";
  }

=head1 DESCRIPTION

This adaptor provides database connectivity for VariationFeature objects.
Genomic locations of variations can be obtained from the database using this
adaptor.  See the base class BaseFeatureAdaptor for more information.

=head1 AUTHOR - Graham McVicker

=head1 CONTACT

Post questions to the Ensembl development list ensembl-dev@ebi.ac.uk

=head1 METHODS

=cut

use strict;
use warnings;

package Bio::EnsEMBL::Variation::DBSQL::VariationFeatureAdaptor;

use Bio::EnsEMBL::Variation::VariationFeature;
use Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

our @ISA = ('Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor');



=head2 fetch_all_by_Variation

  Arg [1]    : Bio::EnsEMBL:Variation::Variation $var
  Example    : my @vfs = @{$vfa->fetch_all_by_Variation($var)};
  Description: Retrieves all variation features for a given variation.  Most
               variations should only hit the genome once and only a return
               a single variation feature.
  Returntype : reference to list Bio::EnsEMBL::Variation::VariationFeature
  Exceptions : throw on bad argument
  Caller     : general
  Status     : Stable

=cut


sub fetch_all_by_Variation {
  my $self = shift;
  my $var  = shift;

  if(!ref($var) || !$var->isa('Bio::EnsEMBL::Variation::Variation')) {
    throw('Bio::EnsEMBL::Variation::Variation arg expected');
  }

  if(!defined($var->dbID())) {
    throw("Variation arg must have defined dbID");
  }

  return $self->generic_fetch("vf.variation_id = ".$var->dbID());
}

=head2 fetch_all_genotyped_by_Slice

  Arg [1]    : Bio::EnsEMBL:Variation::Slice $slice
  Example    : my @vfs = @{$vfa->fetch_all_genotyped_by_Slice($slice)};
  Description: Retrieves all variation features that have been gentoyped for a given slice.
               Most variations should only hit the genome once and only a return
               a single variation feature.
  Returntype : reference to list Bio::EnsEMBL::Variation::VariationFeature
  Exceptions : throw on bad argument
  Caller     : general
  Status     : Stable

=cut

sub fetch_all_genotyped_by_Slice{
    my $self = shift;
    my $slice = shift;

    my $constraint = "vf.flags & 1";
    #call the method fetch_all_by_Slice_constraint with the genotyped constraint
    return $self->fetch_all_by_Slice_constraint($slice,$constraint);
}


=head2 fetch_all_with_annotation_by_Slice

  Arg [1]    : Bio::EnsEMBL:Variation::Slice $slice
  Arg [2]    : $variation_feature_source [optional]
  Arg [3]    : $annotation_source [optional]
  Arg [4]    : $annotation_name [optional]
  Example    : my @vfs = @{$vfa->fetch_all_with_annotation_by_Slice($slice)};
  Description: Retrieves all variation features associated with annotations for
               a given slice.
			   The optional $variation_feature_source argument can be used to
			   retrieve only variation features from a paricular source.
			   The optional $annotation source argument can be used to
               retrieve only variation features with annotations provided by
               a particular source.
			   The optional $annotation_name argument can
               be used to retrieve only variation features associated with
               that annotation.
  Returntype : reference to list Bio::EnsEMBL::Variation::VariationFeature
  Exceptions : throw on bad argument
  Caller     : general
  Status     : Stable

=cut

sub fetch_all_with_annotation_by_Slice{

	my $self = shift;
	my $slice = shift;
	my $v_source = shift;
	my $p_source = shift;
	my $annotation = shift;
	
	if(!ref($slice) || !$slice->isa('Bio::EnsEMBL::Slice')) {
		throw('Bio::EnsEMBL::Slice arg expected');
	}
	
	my $extra_sql = '';
    
    if(defined $v_source) {
		$extra_sql .= qq{ AND s.name = '$v_source' };
    }
    
    if(defined $p_source) {
		$extra_sql .= qq{ AND ps.name = '$p_source' };
    }
    
    if(defined $annotation) {
		$extra_sql .= qq{ AND p.name = '$annotation' };
    }
    
    my $cols = join ",", $self->_columns();
    
    my $sth = $self->prepare(qq{
		SELECT $cols
		FROM variation_feature vf, variation_annotation va,
		phenotype p, source s, source ps # need to link twice to source
		WHERE va.source_id = ps.source_id
		AND vf.source_id = s.source_id
		AND vf.variation_id = va.variation_id
		AND va.phenotype_id = p.phenotype_id
		$extra_sql
		AND vf.seq_region_id = ?
		AND vf.seq_region_end > ?
		AND vf.seq_region_start < ?
		GROUP BY vf.variation_feature_id
    });
    
    $sth->execute($slice->get_seq_region_id, $slice->start, $slice->end);
    
    return $self->_objs_from_sth($sth);
}

# method used by superclass to construct SQL
sub _tables { return (['variation_feature', 'vf'],
		      [ 'source', 's']); }


sub _default_where_clause {
  my $self = shift;

  return 'vf.source_id = s.source_id';
}

sub _columns {
  return qw( vf.variation_feature_id vf.seq_region_id vf.seq_region_start
             vf.seq_region_end vf.seq_region_strand vf.variation_id
             vf.allele_string vf.variation_name vf.map_weight s.name vf.validation_status vf.consequence_type);
}



sub _objs_from_sth {
  my ($self, $sth, $mapper, $dest_slice) = @_;

  #
  # This code is ugly because an attempt has been made to remove as many
  # function calls as possible for speed purposes.  Thus many caches and
  # a fair bit of gymnastics is used.
  #

  my $sa = $self->db()->dnadb()->get_SliceAdaptor();

  my @features;
  my %slice_hash;
  my %sr_name_hash;
  my %sr_cs_hash;

  my ($variation_feature_id, $seq_region_id, $seq_region_start,
      $seq_region_end, $seq_region_strand, $variation_id,
      $allele_string, $variation_name, $map_weight, $source_name, $validation_status, $consequence_type );

  $sth->bind_columns(\$variation_feature_id, \$seq_region_id,
                     \$seq_region_start, \$seq_region_end, \$seq_region_strand,
                     \$variation_id, \$allele_string, \$variation_name,
                     \$map_weight, \$source_name, \$validation_status, \$consequence_type);

  my $asm_cs;
  my $cmp_cs;
  my $asm_cs_vers;
  my $asm_cs_name;
  my $cmp_cs_vers;
  my $cmp_cs_name;
  if($mapper) {
    $asm_cs = $mapper->assembled_CoordSystem();
    $cmp_cs = $mapper->component_CoordSystem();
    $asm_cs_name = $asm_cs->name();
    $asm_cs_vers = $asm_cs->version();
    $cmp_cs_name = $cmp_cs->name();
    $cmp_cs_vers = $cmp_cs->version();
  }

  my $dest_slice_start;
  my $dest_slice_end;
  my $dest_slice_strand;
  my $dest_slice_length;
  if($dest_slice) {
    $dest_slice_start  = $dest_slice->start();
    $dest_slice_end    = $dest_slice->end();
    $dest_slice_strand = $dest_slice->strand();
    $dest_slice_length = $dest_slice->length();
  }

  FEATURE: while($sth->fetch()) {
    #get the slice object
    my $slice = $slice_hash{"ID:".$seq_region_id};
    if(!$slice) {
      $slice = $sa->fetch_by_seq_region_id($seq_region_id);
      $slice_hash{"ID:".$seq_region_id} = $slice;
      $sr_name_hash{$seq_region_id} = $slice->seq_region_name();
      $sr_cs_hash{$seq_region_id} = $slice->coord_system();
    }
    #
    # remap the feature coordinates to another coord system
    # if a mapper was provided
    #
    if($mapper) {
      my $sr_name = $sr_name_hash{$seq_region_id};
      my $sr_cs   = $sr_cs_hash{$seq_region_id};

      ($sr_name,$seq_region_start,$seq_region_end,$seq_region_strand) =
        $mapper->fastmap($sr_name, $seq_region_start, $seq_region_end,
                          $seq_region_strand, $sr_cs);

      #skip features that map to gaps or coord system boundaries
      next FEATURE if(!defined($sr_name));

      #get a slice in the coord system we just mapped to
      if($asm_cs == $sr_cs || ($cmp_cs != $sr_cs && $asm_cs->equals($sr_cs))) {
        $slice = $slice_hash{"NAME:$sr_name:$cmp_cs_name:$cmp_cs_vers"} ||=
          $sa->fetch_by_region($cmp_cs_name, $sr_name,undef, undef, undef,
                               $cmp_cs_vers);
      } else {
        $slice = $slice_hash{"NAME:$sr_name:$asm_cs_name:$asm_cs_vers"} ||=
          $sa->fetch_by_region($asm_cs_name, $sr_name, undef, undef, undef,
                               $asm_cs_vers);
      }
    }

    #
    # If a destination slice was provided convert the coords
    # If the dest_slice starts at 1 and is foward strand, nothing needs doing
    #
    if($dest_slice) {
      if($dest_slice_start != 1 || $dest_slice_strand != 1) {
        if($dest_slice_strand == 1) {
          $seq_region_start = $seq_region_start - $dest_slice_start + 1;
          $seq_region_end   = $seq_region_end   - $dest_slice_start + 1;
        } else {
          my $tmp_seq_region_start = $seq_region_start;
          $seq_region_start = $dest_slice_end - $seq_region_end + 1;
          $seq_region_end   = $dest_slice_end - $tmp_seq_region_start + 1;
          $seq_region_strand *= -1;
        }

        #throw away features off the end of the requested slice
        if($seq_region_end < 1 || $seq_region_start > $dest_slice_length) {
          next FEATURE;
        }
      }
      $slice = $dest_slice;
    }
    $validation_status = 0 if (!defined $validation_status);
    my @states = split(',',$validation_status);
 
    my @types = split(',',$consequence_type); #get the different consequence types
 
    # consequence_type
    push @features, $self->_create_feature_fast('Bio::EnsEMBL::Variation::VariationFeature',
    #push @features, Bio::EnsEMBL::Variation::VariationFeature->new_fast(
    #if use new_fast, then do not need "-" infront of key, i.e 'start' => $seq_region_start,

      {'start'    => $seq_region_start,
       'end'      => $seq_region_end,
       'strand'   => $seq_region_strand,
       'slice'    => $slice,
       'allele_string' => $allele_string,
       'variation_name' => $variation_name,
       'adaptor'  => $self,
       'dbID'     => $variation_feature_id,
       'map_weight' => $map_weight,
       'source'   => $source_name,
       'validation_code' => \@states,
       'consequence_type' => \@types || 'INTERGENIC',
       '_variation_id' => $variation_id});
  }

  return \@features;


}


=head2 list_dbIDs

  Arg [1]    : none
  Example    : @feature_ids = @{$simple_feature_adaptor->list_dbIDs()};
  Description: Gets an array of internal ids for all simple features in 
               the current db
  Returntype : list of ints
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub list_dbIDs {
  my $self = shift;
  return $self->_list_dbIDs('variation_feature');
}


=head2 get_all_synonym_sources

    Args[1]     : Bio::EnsEMBL::Variation::VariationFeature vf
    Example     : my @sources = @{$vf_adaptor->get_all_synonym_sources($vf)};
    Description : returns a list of all the sources for synonyms of this
                  VariationFeature
    ReturnType  : reference to list of strings
    Exceptions  : none
    Caller      : general
    Status      : At Risk
                : Variation database is under development.

=cut

sub get_all_synonym_sources{
    my $self = shift;
    my $vf = shift;
    my %sources;
    my @sources;

    if(!ref($vf) || !$vf->isa('Bio::EnsEMBL::Variation::VariationFeature')) {
	 throw("Bio::EnsEMBL::Variation::VariationFeature argument expected");
    }
    
    if (!defined($vf->{'_variation_id'}) && !defined($vf->{'variation'})){
	warning("Not possible to get synonym sources for the VariationFeature: you need to attach a Variation first");
	return \@sources;
    }
    #get the variation_id
    my $variation_id;
    if (defined ($vf->{'_variation_id'})){
	$variation_id = $vf->{'_variation_id'};
    }
    else{
	$variation_id = $vf->variation->dbID();
    }
    #and go to the varyation_synonym table to get the extra sources
    my $source_name;
    my $sth = $self->prepare(qq{SELECT s.name 
				FROM variation_synonym vs, source s 
				WHERE s.source_id = vs.source_id
			        AND   vs.variation_id = ?
			    });
    $sth->bind_param(1,$variation_id,SQL_INTEGER);
    $sth->execute();
    $sth->bind_columns(\$source_name);
    while ($sth->fetch){
	$sources{$source_name}++;
    }
    @sources = keys(%sources); 
    return \@sources;
}
1;
