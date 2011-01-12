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
   GT
};

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
sub GT  ($$){}
sub LT  ($$){}

# TODO ... or should JOIN be an attr so that you can append?
sub JOIN  ($$){}
sub LJOIN ($$){}





#---------------------------------------------------------------------------
#  OBJECTS
#---------------------------------------------------------------------------
BEGIN {
   package SQL::Query::Builder::Query::Util;
   use Mouse::Role;

   sub flat {
      map {
         ( ref $_ eq 'CODE')  ? flat(&$_) # exec code refs 
       : ( ref $_ eq 'ARRAY') ? flat(@$_) # unpack arrayrefs
       : ( ref $_ eq 'HASH')  ? flat(%$_) # unpack hashrefs
       :                        $_ ;      # other wise just leave it alone
      } @_;
   } ## end sub flat

   sub soq { return join( ',', map {'?'} flat(@_) )}    # a string of ?'s to match @_
};

BEGIN {
   package SQL::Query::Builder::Query::Part;
   use Util::Log;
   use Sub::Identify ':all';
   use Mouse;

   has $_ => 
      is => 'rw',
      isa => 'ArrayRef',
      lazy => 1,
      default => sub{[]},
      clearer => qq{clear_$_},
      predicate => qq{has_$_},
   for qw{query bindvars};

   # just some sane defaults 
   sub input {shift->query(\@_)} # just toss everything in to query
   # NOTE: this will append... we need to work out some syntax to do a clear first if you want to overwrite
   #sub input {my $self = shift;$self->query([@{$self->query},@_])} # just toss everything in to query

   # we are going to assume that most parts are simple lists
   sub output {
      my $self = shift;
      return '*' unless $self->has_query;
      return join ', ', @{ $self->query }
   };
};


BEGIN {
   package SQL::Query::Builder::Query::Part::WHERE;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
   with qw{SQL::Query::Builder::Query::Util};

use Util::Log;
   sub input {
      my $self = shift;
      my %IN   = @_;
      foreach my $key ( keys %IN ) {
DUMP {WHERE => {$key => $IN{$key}}};

         $self->bindvars([ @{$self->bindvars}, flat( $IN{$key} ) ]);
         $self->query([ @{$self->query}, sprintf q{%s = %s}, $key, soq($IN{$key})]);
      }
DUMP {map{$_ => $self->$_} qw{query bindvars}};
   }

   sub output {
      my $self = shift;
      join ', ', @{$self->query};
   }
};

=pod
BEGIN {
   package SQL::Query::Builder::Query::Part::WHAT;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
};

BEGIN {
   package SQL::Query::Builder::Query::Part::FROM;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
};
BEGIN {
   package SQL::Query::Builder::Query::Part::GROUP;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
};

BEGIN {
   package SQL::Query::Builder::Query::Part::HAVING;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
};

BEGIN {
   package SQL::Query::Builder::Query::Part::ORDER;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
};
=cut
BEGIN {
   package SQL::Query::Builder::Query::Part::LIMIT;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};

   sub output { shift->query->[0] || 1 };
};

BEGIN {
   package SQL::Query::Builder::Query;
   use Util::Log;
   use Sub::Identify ':all';
   use Mouse;
   use Mouse::Util::TypeConstraints;

   enum   'SQL_Query_Type' => qw(SELECT INSERT UPDATE DELETE);
   coerce 'SQL_Query_Type' => from 'Str' => via { uc($_) };


   use constant QUERY_PARTS => qw{ WHAT 
                                   FROM
                                   WHERE
                                   GROUP
                                   HAVING
                                   ORDER
                                   LIMIT
                                 };

   has type => 
      is => 'ro',
      isa => 'SQL_Query_Type',
      coerce => 1,
      required => 1,
   ;

   for my $part (QUERY_PARTS) {
      has qq{$part} =>
         is => 'rw',
         isa => qq{SQL::Query::Builder::Query::Part},
         lazy => 1,
         default => sub{

            # TODO: this will have to change when broken to there own files
            my $out;
            eval { my $class = qq{SQL::Query::Builder::Query::Part::$part};
                   $out = $class->new;
                 } or do { $out = SQL::Query::Builder::Query::Part->new };
            $out;

            #require SQL::Query::Builder::Query::Part;
            #my $class = qq{SQL::Query::Builder::Query::Part::$part};
            #eval qq{require $class} or do {$class = q{SQL::Query::Builder::Query::Part};} ;
            #$class->new;
         }, 
         handles => { # my => there
                      qq{has_query_$part}      => q{has_query},
                      qq{clear_query_$part}    => q{clear_query},
                      qq{has_bindvars_$part}   => q{has_bindvars},
                      qq{clear_bindvars_$part} => q{clear_bindvars},
                    },
         predicate => qq{has_$part},
         clearer => qq{clear_$part},
      ;
   
      # I want to keep the 'moose' API where you have one method that deligates to 
      # get or set the value, though this attr is an object. I don't want to reset
      # the object, I want to set values in the object. Though 'has' builds us our
      # the method to access the object, but it's going to point to the wrong place.
      # This modifier corrects this so we can still call 'WHAT' but it pushes the 
      # data passed to WHAT->input(@_) and input will do 'the right thing' from there.

      # Also while we are looping, I want to be able to chain these methods if they 
      # are called in 'setter' mode. Note the 'do' block returns $self.
      around $part => sub{
         my $next = shift;
         my $self = shift;
         return @_ ? do{$self->$next->input(@_);$self} : $self->$next->output;
      };

   }

   sub _raw {
      my $self      = shift;
      [$self->meta->get_method_list];
   };

   sub dbi   { shift }
   sub build { 
      my $self = shift;
      my @query = grep{ defined }
                    $self->type
                  , join( ', ', $self->WHAT) || undef 
                  , FROM => $self->FROM,
                  , WHERE => $self->WHERE
                  , map {$_, $self->$_} 
                    grep{my $has = qq{has_$_};$self->$has}
                    qw{ GROUP HAVING ORDER LIMIT }
                  ;
use Util::Log;
DUMP {RAW => $self->_raw('WHAT')};

      my $q = join ' ', @query;
      return $q, 
   }
   
   no Mouse::Util::TypeConstraints;
   no Mouse;

};


BEGIN {
   package SQL::Query::Builder::Query::Select;
   use Mouse;
   extends qw{SQL::Query::Builder::Query};

   has '+type' => default => 'SELECT';

};

   
1;

