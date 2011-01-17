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

sub AND ($) { SQL::Query::Builder::Query::Part::Set->new( type => 'AND', data => $_[0]); }
sub OR  ($) { SQL::Query::Builder::Query::Part::Set->new( type => 'OR' , data => $_[0]); }
sub IN  ($) { SQL::Query::Builder::Query::Part::Set::IN->new( data => $_[0]); }

sub GT  ($) { SQL::Query::Builder::Query::Part::OpValuePair->new(type => '>' , data => \@_); }
sub GTE ($) { SQL::Query::Builder::Query::Part::OpValuePair->new(type => '>=', data => \@_); }
sub LT  ($) { SQL::Query::Builder::Query::Part::OpValuePair->new(type => '<' , data => \@_); }
sub LTE ($) { SQL::Query::Builder::Query::Part::OpValuePair->new(type => '<=', data => \@_); }

sub JOIN ($$) { SQL::Query::Builder::Query::Part::JOIN->new( data => \@_ ); }
sub LJOIN($$) { SQL::Query::Builder::Query::Part::JOIN->new(type => 'LEFT', data => \@_); }


#---------------------------------------------------------------------------
#  Query
#---------------------------------------------------------------------------
BEGIN {
   package SQL::Query::Builder::Query::Util;
   use Mouse::Role;

   sub back_tick {
      my $item = shift;
      $item =~ s/[.]/`.`/g;
      return qq{`$item`};
   }

   sub flat {
      map { ( ref $_ eq 'ARRAY') ? flat(@$_) #unpack arrayrefs
          : ( ref $_ eq 'HASH')  ? flat(%$_) #unpack hashrefs
          :                        $_ ;      #other wise just leave it alone
          } @_;
   } 

   # a string of ?'s to match @_
   sub soq {
      join( ',', map {'?'} flat(@_) );
   }

};

BEGIN {
   package SQL::Query::Builder::Query::Part;
   use Mouse;
   use Scalar::Util qw{blessed};

   has $_ => 
      is => 'rw',
      isa => 'Maybe[Str]',
      lazy => 1,
      default => '',
      clearer => qq{clear_$_},
      predicate => qq{has_$_},
   for qw{type column} ;

   has data => 
      is => 'rw',
      isa => 'ArrayRef',
      lazy => 1,
      default => sub{[]},
      clearer => qq{clear_data},
      predicate => qq{has_data},
   ;

   has joiner => 
      is => 'rw',
      isa => 'Str',
      default => ', ',
   ;

   has pass_to_build => 
      is => 'rw',
      isa => 'ArrayRef',
      default => sub{[]},
   ;

   # build returns a partial query string and an arrayref of bind vars
   sub build { 
      my $self = shift;
      return undef, [] unless $self->has_data;
      my @q;
      my @bv;
      foreach my $item (@{ $self->data }) {
         my ($q,$bv) = blessed($item) && $item->can('build') ? $item->build(map{$self->$_} @{ $self->pass_to_build }) : $item;
         push @q, $q;
         push @bv, @{ $bv || [] };
      }

      return join( $self->joiner, grep{defined} @q), \@bv;
      
   }
}

BEGIN {
   package SQL::Query::Builder::Query::Part::OpValuePair;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
   with qw{SQL::Query::Builder::Query::Util};

   has '+joiner' => default => ' ';

   # TODO : This should look at data to see if it needs to run build or not?
   sub build {
      my $self = shift;
      my $q = join $self->joiner, grep{defined} 
                                 $self->has_column ? back_tick( $self->column ) : undef 
                                , $self->has_type   ?  $self->type               : undef # should never happen
                                , soq( $self->data );
      return $q, $self->data;
   }
};
   

BEGIN {
   package SQL::Query::Builder::Query::Part::Set;
   use Mouse;
   use Scalar::Util qw{blessed};
   use List::MoreUtils qw{natatime};
   extends qw{SQL::Query::Builder::Query::Part};
   with qw{SQL::Query::Builder::Query::Util};


   has note => is => 'rw', isa => 'Str', default => ''; # DEBUGGING mostly

   has '+pass_to_build' => default => sub{[qw{column}]};

   sub OVP ($$) { SQL::Query::Builder::Query::Part::OpValuePair->new(type => '=', column => shift, data => [shift]) };
   sub SET { SQL::Query::Builder::Query::Part::Set->new( @_ ); }
   sub SOR { SET( type => 'OR' , @_ ) }
   sub SAND{ SET( type => 'AND', @_ ) }

   # set the joiner to the type for simplicity later
   sub BUILD {
      my $self = shift;
      $self->joiner( sprintf q{ %s }, $self->type );
   }

   around build => sub{
      my $next = shift;
      my $self = shift;

      my @data = map{ my $ref = ref($_);
                      $ref eq 'ARRAY' ? SOR @$_  # col => [...] ==> col => OR [...]
                    : $ref eq 'HASH'  ? SAND %$_ # col => {...} ==> col => AND{...} 
                    : $ref            ? $_->has_column ? $_ : do{ $_->column($self->column); $_ } # push along $col if it's needed
                    :                   OVP $self->column => $_ ;
                    } @{ $self->data };
         

      $self->data(\@data);

      my ($q,$bv) = $self->$next(@_);
      
      return scalar( @{ $self->data } ) > 1 
           ? (sprintf( q{(%s)}, $q), $bv) # wrap output in parens if there are more then one pair
           : ($q, $bv) ;
   };

}

BEGIN {
   package SQL::Query::Builder::Query::Part::Set::IN;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
   with qw{SQL::Query::Builder::Query::Util};

   has '+joiner' => default => ', ';

   sub build {
      my $self = shift;
      my $q = defined $self->column ? back_tick($self->column) : ''; 
      $q .= sprintf q{%sIN (%s)}, length($q) ? ' ' : '', soq($self->data);
      return $q, $self->data;
   }

};


BEGIN {
   package SQL::Query::Builder::Query::Part::WHERE;
   use Mouse;
   use Scalar::Util qw{blessed};
   use List::MoreUtils qw{natatime};

   extends qw{SQL::Query::Builder::Query::Part};
   with qw{SQL::Query::Builder::Query::Util};

   sub OVP ($$) { SQL::Query::Builder::Query::Part::OpValuePair->new(type => '=', column => shift, data => [shift]) };
   sub SET { SQL::Query::Builder::Query::Part::Set->new( @_ ); }
   sub SOR { SET( type => 'OR' , @_ ) }
   sub SAND{ SET( type => 'AND', @_ ) }

   sub build {
      my $self = shift;
      my @data;

      my $pairs = natatime 2, @{ $self->data };
      while (my @pair = $pairs->()) {
         my ($col, $val) = @pair;

         my $ref = ref($val);
         push @data, $ref eq 'ARRAY'             ? SOR  column => $col, data => $val  # col => [...] ==> col => OR [...]
                   # TODO this conflicts with old-style col => { '>' => 1 }
                   : $ref eq 'HASH'              ? SAND column => $col,  data => [%$val] # col => {...} ==> col => AND{...} 
                   : $ref && $val->can('column') ? $val->has_column ? $val : do{ $val->column($col); $val } # push along $col if it's needed
                   : $ref                        ? $val # no clue... pass along
                   :                               OVP $col => $val ;


      }

      # now build an AND set to do the join/build step for us
      SAND( note => 'WHERE wrapper', data => \@data )->build;
   }

}

BEGIN {
   package SQL::Query::Builder::Query::Part::JOIN;
   use Mouse;
   extends qw{SQL::Query::Builder::Query::Part};
   with qw{SQL::Query::Builder::Query::Util};

   has '+type' => default => '';

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
                                                            while (my ($k,$v) = map{back_tick($_)} each %$hash) {
                                                               push @out, qq{$k = $v};
                                                            }
                                                            sprintf q{ON (%s)}, join ' AND ', @out;
                                                          }
                                                      : sprintf( q{USING (%s)}, back_tick( $self->data->[1] ))
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
   with qw{SQL::Query::Builder::Query::Util};

   has '+type' => default => 'SELECT';
   has column => 
      is => 'rw',
      isa => 'Maybe[Str]',
      lazy => 1,
      default => '',
      clearer => qq{clear_column},
      predicate => qq{has_column},
   ;

   around build => sub{
      my $next = shift;
      my $self = shift;

      my ($q,$bv) = $self->$next(@_);
      return $self->has_column ? ( sprintf( q{%s = (%s)}, back_tick( $self->column ), $q), $bv )
                               : ($q, $bv)
   };
      
};


__END__
TODO:
- would it make any sence to just have SELECT be a QUERY::PART ? 
-- the thinking is that they already share the same API
--- build is very simular

- I would like to move type and column to a role that you include
-- it would be nice that col would 'auto-back_tick' on read or possibly on insert?
