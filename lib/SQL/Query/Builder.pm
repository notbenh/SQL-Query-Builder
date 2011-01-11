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
   #$q->WHAT(@_ ? @_ : '*'); # not given as part of new to trip the build in 'coerce' hook
   return $q;
}

sub AND ($) {}
sub OR  ($) {}
sub IN  ($) {}
sub GT  ($$){}
sub LT  ($$){}





#---------------------------------------------------------------------------
#  OBJECTS
#---------------------------------------------------------------------------
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
   sub output{
      my $self = shift;
      return [$self->query, $self->bindvars];
   }
};

BEGIN {
   package SQL::Query::Builder::Query::Part::WHAT;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};

   sub output {
      my $self = shift;
      return '*' unless $self->has_query;
      return join ', ', @{ $self->query }};
};

BEGIN {
   package SQL::Query::Builder::Query::Part::FROM;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
};

BEGIN {
   package SQL::Query::Builder::Query::Part::WHERE;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
=pod
   # WHERE is really a hash, treat it as such
   around WHERE => sub{
      my $next = shift;
      my $self = shift;
      return $self->$next(@_) if @_; # DO NOT MODIFY if we are trying to set a value
      my %WHERE = $self->$next();
      DUMP {WHERE => \%WHERE};
      my @out;
      # we need to unzip keys and values, but we need them to remain in 'sync' two arrays are used
      foreach my $key (keys %WHERE) {
         my $value = $WHERE{$key};
         push @{$self->bindvars}, $value;
         push @out, sprintf qq{%s = ?}, $key ;
      }
      
      
      @out;
   };
=cut
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

BEGIN {
   package SQL::Query::Builder::Query::Part::LIMIT;
   use Util::Log;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
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
            my $class = qq{SQL::Query::Builder::Query::Part::$part};
            eval qq{require $class};
            $class->new;
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

   sub dbi   { shift }
   sub build { 
      my $self = shift;
      my @query = grep{ defined }
                    $self->type
                  , join( ', ', $self->WHAT) || undef 
                  , map {$_, $self->$_} 
                    grep{my $has = qq{has_$_};$self->$has}
                    grep{$_ !~ m/(?:WHAT)/} 
                    QUERY_PARTS
                  ;

      DUMP {Q => \@query};
      return join ' ', @query;
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

   
