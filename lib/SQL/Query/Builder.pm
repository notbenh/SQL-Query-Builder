package SQL::Query::Builder;
use strict;
use warnings;
use Exporter qw{import};
our @EXPORT = qw{
   SELECT

   AND 
   OR
   IN

   LT
   LTE
   GT
   GTE
   
   JOIN 
   LJOIN
};

# ABSTRACT: a completely OO driven way to build SQL queries.

sub SELECT { 
   my $q = SQL::Query::Builder::Query::Select->new;
   $q->WHAT(@_ ? @_ : '*'); # not given as part of new to trip the build in 'coerce' hook
   return $q;
}

# TODO !!! we will need to have some syntax to append vs overwrite
# currently $query = SELECT->FROM('table')->WHERE(...)->LIMIT(1);
# $query->FROM('other'); # would expect to be FROM('table', 'other') but currently this will just be FROM('other')


# TODO There is two diffrent context for sets 
# col => OR[1,2]         ==> col = 1 OR col = 2
# OR{col => 1, val => 2} ==> col = 1 OR val = 2

sub AND ($) {}
sub OR  ($) {}
sub IN  ($) {}

sub GT  ($) {{'>' =>shift}}
sub GTE ($) {{'>='=>shift}}
sub LT  ($) {{'<' =>shift}}
sub LTE ($) {{'<='=>shift}}

sub JOIN ($$) { my $j = SQL::Query::Builder::Query::Part::JOIN->new; $j->data(\@_); $j}
sub LJOIN($$) { my $j = SQL::Query::Builder::Query::Part::JOIN->new(type => 'LEFT'); $j->data(\@_); $j}


#---------------------------------------------------------------------------
#  Query
#---------------------------------------------------------------------------
BEGIN {
   package SQL::Query::Builder::Query::Part;
   use Mouse;
   use Scalar::Util qw{blessed};

   has type => 
      is => 'ro',
      isa => 'Maybe[Str]',
   ;

   has data => 
      is => 'rw',
      isa => 'ArrayRef',
      lazy => 1,
      default => sub{[]},
      clearer => qq{clear_data},
      predicate => qq{has_data},
   ;

   # build returns a partial query string and an arrayref of bind vars
   sub build { 
      my $self = shift;
      return undef, [] unless $self->has_data;
      my @q;
      my @bv;
      foreach my $item (@{ $self->data }) {
         my ($q,$bv) = blessed($item) && $item->can('build') ? $item->build : $item;
         push @q, $q;
         push @bv, @{ $bv || [] };
      }

      return join( ', ', grep{defined} @q), \@bv;
      
   }
}

BEGIN {
   package SQL::Query::Builder::Query::Part::WHERE;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};

}

BEGIN {
   package SQL::Query::Builder::Query::Part::JOIN;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};

   has type => 
      is => 'ro', 
      isa => 'Str',
      default => '',
   ;

   # TODO due to part's default join ', ' we are ending up with "FROM table, JOIN table" => bad

   # TODO the JOIN table => {} notation should hand that hash to WHERE

   sub build {
      my $self = shift;
      my $q = sprintf q{%sJOIN %s %s}, 
                      length($self->type) ? $self->type . ' ' : ''
                    , $self->data->[0]
                    , ref($self->data->[1]) eq 'HASH' ? do{ # TODO this really should be a handoff to WHERE->
                                                            my $hash = $self->data->[1];
                                                            my @out;
                                                            while (my ($k,$v) = map{s/[.]/`.`/g;$_} each %$hash) {
                                                               push @out, qq{`$k` = `$v`};
                                                            }
                                                            sprintf q{ON (%s)}, join ' AND ', @out;
                                                          }
                                                      : sprintf( q{USING (%s)}, $self->data->[1])
      ;
      return $q, [];
   }
              

}


BEGIN {
   package SQL::Query::Builder::Query;
   use Mouse;

   has type => 
      is => 'ro',
      isa => 'Str',
   ;

   # TODO there should be some way to altering this list from the outside for other query types
   use constant QUERY_PARTS => qw{WHAT FROM WHERE HAVING GROUP ORDER LIMIT};

   for my $part (QUERY_PARTS) {
      has $part => 
         is => 'rw',
         isa => 'SQL::Query::Builder::Query::Part',
         lazy => 1,
         default => sub{
            my $out;

            my $part_type = $part eq 'GROUP' ? 'GROUP BY'
                          : $part eq 'WHAT'  ? undef
                          :                    $part;
            eval { 
               my $class = qq{SQL::Query::Builder::Query::Part::$part};
               $out = $class->new( type => $part_type );
            } or do {
               #warn "ERROR: $@";
               $out = SQL::Query::Builder::Query::Part->new( type => $part_type );
            };
            $out;
         },
         clearer => qq{clear_$part},
         predicate => qq{has_$part},
      ;
   }

   around [QUERY_PARTS] => sub{
      my $next = shift;
      my $self = shift;
      # return self if in 'setter' mode to allow for chainging
      return @_ ? do{$self->$next->data(\@_);$self} : $self->$next;
   };


   sub dbi { 
      my $self = shift;
      my $argv = scalar(@_) == 1 && ref($_[0]) eq 'HASH' ? $_[0] : {@_};
      my ($q,$bind) = $self->build;
      return ($q,$argv,@{ $bind || [] });
   }

   sub build { 
      my $self = shift;
      my @q;
      my @bv;
      foreach my $part (QUERY_PARTS) {
         my $predicate = qq{has_$part};
         next unless $self->$predicate;
         
         my ($q,$bv) = $self->$part->build;
         push @q, $self->$part->type, $q;
         push @bv, @$bv;
      }

      return join( ' ', $self->type, grep{defined} @q), \@bv;
      
   }
      
};

BEGIN {
   package SQL::Query::Builder::Query::Select;
   use Mouse;
   extends qw{SQL::Query::Builder::Query};

   has '+type' => default => 'SELECT';
};

