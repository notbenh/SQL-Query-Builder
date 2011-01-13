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

sub JOIN ($$) {}
sub LJOIN($$) {}


#---------------------------------------------------------------------------
#  Query
#---------------------------------------------------------------------------
BEGIN {
   package SQL::Query::Builder::Query;
   use Mouse;

   use constant QUERY_PARTS => qw{WHAT FROM WHERE HAVING GROUP ORDER LIMIT};

   has $_ => 
      is => 'rw',
      isa => 'ArrayRef',
      lazy => 1,
      default => sub{[]},
      clearer => qq{clear_$_},
      predicate => qq{has_$_},
   for QUERY_PARTS;

   around [QUERY_PARTS] => sub{
      my $next = shift;
      my $self = shift;
      my $rv = $self->$next(\@_);
      return @_ ? $self : $rv; # return self if in 'setter' mode, allows for chains
   };


   sub dbi { 
      my $self = shift;
      my $argv = scalar(@_) == 1 && ref($_[0]) eq 'HASH' ? $_[0] : {@_};
      my ($q,$bind) = $self->build;
      return ($q,$argv,@{ $bind || [] });
   }

   sub build { shift }; # for now return self
      
};

BEGIN {
   package SQL::Query::Builder::Query::Select;
   use Mouse;
   extends qw{SQL::Query::Builder::Query};
};

