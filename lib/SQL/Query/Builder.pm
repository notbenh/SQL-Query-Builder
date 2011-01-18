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
   EQ

   NOT
   
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


sub SET ($$){ my ($type,$val) = @_;
              my @data = ref($val) eq 'ARRAY' ? @$val
                       : ref($val) eq 'HASH'  ? map{ SQL::Query::Builder::Query::Part::OpValuePair->new(type => '=' , data => [$val->{$_}], column => $_) } keys %$val
                       :                        $val;
              SQL::Query::Builder::Query::Part::Set->new( type => $type , data => \@data); 
            }

sub AND ($) { SET AND => shift }
sub OR  ($) { SET OR  => shift }
sub IN  ($) { SQL::Query::Builder::Query::Part::Set::IN->new( data => $_[0]); }

# TODO I'm not really sold yet on having an generic OVP builder 
sub OVP ($$){ use Scalar::Util qw{blessed};
              my ($op, $val) = @_;
              blessed($val) && $val->isa('SQL::Query::Builder::Query::Part::OpValuePair') 
              ? $val # passthru
              : SQL::Query::Builder::Query::Part::OpValuePair->new(type => $op , data => $val); 
            }
sub GT  ($) { OVP '>'  => \@_ }
sub GTE ($) { OVP '>=' => \@_ }
sub LT  ($) { OVP '<'  => \@_ }
sub LTE ($) { OVP '<=' => \@_ }
sub EQ  ($) { OVP '='  => \@_ }

sub NOT ($) { die 'not built yet' }; # TODO this should take an OVP (or build an EQ) and then prepend the op with '!'

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

   has note => is => 'rw', isa => 'Str', default => ''; # DEBUGGING mostly not used durring build

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
   package SQL::Query::Builder::Query::Part::FROM;
   use Mouse;
   use Scalar::Util qw{blessed};
   use List::Bisect;
   extends qw{SQL::Query::Builder::Query::Part};
   with qw{SQL::Query::Builder::Query::Util};
   
   around build => sub {
      my $next = shift;
      my $self = shift;
      my ($J,$T) = bisect {blessed($_) && $_->isa('SQL::Query::Builder::Query::Part::JOIN')} @{ $self->data };
      
      push @$T, join ' ', pop @$T, map{ [$_->build]->[0] } @$J; # TODO this relies on JOIN NEVER having any bindvars
      $self->data($T);
      $self->$next(@_);
   };
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

      my @raw = @{ $self->data };
      while ( my ($col,$val) = splice @raw, 0, 2 ) {
         if( ref($col) ) {
            # wait... col should never be anything other then a scalar. can be triggered like WHERE(OR{...},col => 1)
            unshift @raw, $val if defined $val; # might be the end of the stack, no need to make extra messes
            $val = $col;
            $col = undef;
         } 

         my $ref = ref($val);
         push @data, $ref eq 'ARRAY'             ? SOR  column => $col, data => $val  # col => [...] ==> col => OR [...]
                   # TODO this conflicts with old-style col => { '>' => 1 }
                   : $ref eq 'HASH'              ? SAND column => $col,  data => [%$val] # col => {...} ==> col => AND{...} 
                   : $ref && $val->can('column') ? $val->has_column ? $val : do{ $val->column($col); $val } # push along $col if it's needed
                   : $ref                        ? $val # no clue... pass along
                   : !defined $val && ref($col)  ? $col # likely a bare SET
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

   # TODO the JOIN table => {} notation should hand that hash to WHERE as to build out things correctly

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


- one idea for the FROM JOIN issue is to bisect {is_join} and then join all JOINs and the last item of non-JOINs by ' ' then push that back as the last item of the non-JOINs and then join all non-JOINs with ', '... messy but should work. 
-- really highlites the need that PART::build to be a bit more abstract to plug in features like this.
--- look at all builds to see if there are things that should be broken out?


__END__
simple 'finder' wrapper:

package My::Finder;
use Mouse;
extends qw{ SQL::Query::Builder::Query::Select };
with qw{
   MooseP::Setup::Database
   MooseP::Setup::Cache
};

has '+WHAT' => default => sub{[qw{this that}]};
has '+FROM' => default => sub{[qw{table}]};

sub find {
   my $self = shift;
   $self->WHERE(@_);
   return $self->d->selectall_arrayref($self->dbi({Slice=>{}}) );
}

# would be global to some base finder obj
around find {
   my $next = shift;
   my $self = shift;
   my $key  = $self->cache->build_key(__PACKAGE__ => @_);
   $self->cache->get($key) || do{ my $val = $self->$next(@_); $self->cache->set($key, $val, $self->expire); $val};
}
     


