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

   sub input {}
   sub output{}
};

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
   package SQL::Query::Builder::Query::Part::WHERE;
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
         #auto_deref => 1, 
         default => sub{
            my $class = qq{SQL::Query::Builder::Query::Part::$part};
            eval qq{require $class};
            $class->new;
         }, 
         handles => { # my => there
                      #qq{read_$part}           => q{output},
                      #qq{write_$part}          => q{input},
                      qq{has_query_$part}      => q{has_query},
                      qq{clear_query_$part}    => q{clear_query},
                      qq{has_bindvars_$part}   => q{has_bindvars},
                      qq{clear_bindvars_$part} => q{clear_bindvars},
                    },
         predicate => qq{has_$part},
         clearer => qq{clear_$part},
      ;

      # because this attr is really an obj, we want to point at the right method based on context
      # if we are setting a value, then pass it to the objects input method, else call output
      # this allows this object to look like a simple attr from the API standpoint
      around $part => sub{
         my $next = shift;
         my $self = shift;
         return @_ ? $self->$next->input(@_) : $self->$next->output;
      };
   }

   # allow for chaining when setting values;
   around [QUERY_PARTS] => sub {
      my $next = shift;
      my $self = shift;
      # DO NOT CHAIN if we are just attempting to access the value of this attr
      # we 'coerce' here vs building a type as type coerce only takes the first value, we want all input
      my $rv = $self->$next( scalar(@_) == 0                          ? @_    # this is an accessor, just get value
                           : scalar(@_) == 1 && ref($_[0]) eq 'ARRAY' ? $_[0] # we were passed an arrayref, store it
                           :                                            \@_   # 'coerce': ref what was passed 
                           );
      return @_ ? $self : defined $rv ? @$rv : undef;
   };
=pod
=cut
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
   sub dbi   { shift }
   sub build { 
      my $self = shift;
      #$self->clear_bindvars; # clear out any old cruft to rebuild again;
      
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

   
