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

sub JOIN ($$) { my $j = SQL::Query::Builder::Query::Part::JOIN->new; $j->input(\@_); $j}
sub LJOIN($$) { my $j = SQL::Query::Builder::Query::Part::JOIN->new(type => 'LEFT'); $j->input(\@_); $j}


#---------------------------------------------------------------------------
#  Query
#---------------------------------------------------------------------------
BEGIN {
   package SQL::Query::Builder::Query::Part;
   use Mouse;

   has data => 
      is => 'rw',
      isa => 'ArrayRef',
      lazy => 1,
      default => sub{[]},
      clearer => qq{clear_data},
      predicate => qq{has_data},
      writer => 'input',
      reader => 'output',
   ;

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

}


BEGIN {
   package SQL::Query::Builder::Query;
   use Mouse;

   use constant QUERY_PARTS => qw{WHAT FROM WHERE HAVING GROUP ORDER LIMIT};

   for my $part (QUERY_PARTS) {
      has $part => 
         is => 'rw',
         isa => 'SQL::Query::Builder::Query::Part',
         lazy => 1,
         default => sub{
            my $out;
            eval { 
               my $class = qq{SQL::Query::Builder::Query::Part::$part};
               $out = $class->new;
            } or do {
               #warn "ERROR: $@";
               $out = SQL::Query::Builder::Query::Part->new;
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
      my $rv = $self->$next->input(\@_);
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

