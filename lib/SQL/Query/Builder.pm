package SQL::Query::Builder;
use strict;
use warnings;
use Exporter qw{import};
our @EXPORT = qw{
   SQL
   SELECT
   UPDATE
   INSERT
   DELETE

   gt
   gte
   lt
   lte

   AND 
   OR
   NOT
};
our %EXPORT_TAGS = (all => \@EXPORT);


BEGIN {
   package Util::DB::QueryBuilder::Set;
   use Moose;
   
   has joiner => 
      is => 'rw',
      isa => 'Str',
      default => 'AND',
   ;
   around joiner => sub{
      my $next = shift;
      my $self = shift;
      my $v = $self->$next(@_);
      $v =~ m/^\s+.*\s+$/ ? $v : qq{ $v }; # auto pad the whitespace
   };

   has value => 
      is => 'rw',
      isa => 'ArrayRef',
      auto_deref => 1,
      required => 1,
   ;

   sub render {
      my $self = shift;
      my $col  = shift;
      my @query;
      my @bind;
      
      foreach my $val ($self->value) {
         my ($q,@b) = $val->render($col);
         push @query, $q;
         push @bind, @b;
      
      }

      return sprintf( @query > 1 ? q{(%s)} : q{%s}
                    , join $self->joiner, @query
                    ), @bind;
   }
}

BEGIN {
   package Util::DB::QueryBuilder::Particle;
   use Moose;
   use Data::Manip qw{flat};

   has op => 
      is => 'rw',
      isa => 'Str',
   ;
   
   has op => 
      is => 'rw',
      isa => 'Str',
      required => 1,
   ;

   has value => 
      is => 'rw',
      isa => 'Any',
      required => 1,
   ;

   sub soq { join ',', map{'?'} flat( shift->value ) }

   sub wrap{ 
      my $self = shift;
      my $str  = $self->soq;
      $self->op =~ m/^(?:IN)$/ ? qq{($str)} : $str;
   }

   sub render {
      my $self = shift;
      my $col  = shift;
      return sprintf( q{`%s` %s %s}, $col, $self->op, $self->wrap($self->value) )
           , $self->value ;
   }

}


BEGIN {
   package Util::DB::QueryBuilder::Builder;
   use Moose;
   use Sub::Identify qw{sub_name};
   use Quantum::Superpositions;
   use Data::Manip qw{flat};

   has query => 
      is => 'ro',
      isa => 'Util::DB::QueryBuilder::Query',
      required => 1,
      #handles => [map{$_, qq{has_$_}} qw{WHAT FROM JOIN WHERE GROUP ORDER LIMIT type}],
   ;

   #---------------------------------------------------------------------------
   #  DSL
   #---------------------------------------------------------------------------
   sub COM (@) { join ', ', @_ };
   sub P ($$) {Util::DB::QueryBuilder::Particle->new(op => shift, value => shift)}
   sub S ($$) {Util::DB::QueryBuilder::Set->new(joiner => shift, value => shift)}

   #---------------------------------------------------------------------------
   #  PARTS
   #---------------------------------------------------------------------------
   sub WHAT { shift->query->WHAT} #simple passthru for now
   sub FROM { shift->query->FROM}
   sub JOIN { return undef; }
   sub WHERE {
      my $self = shift;
      return unless $self->query->has_WHERE;

      my %where = $self->query->WHERE; # unravle some of that deref magic

      my @query;
      my @bind;

      sub upk {
         map { my $x = $_;
               my $r = ref($x);
            $r eq 'ARRAY' ? S OR  => [upk(@$x)]
          : $r eq 'HASH'  ? S AND => [upk(map{ P $_ => $x->{$_}} keys %$_)]  # build a set of particles for everything # !!! NOTE WILL FAIL FOR RAW
          : $r eq 'CODE'  ? upk($x->())
          : $r eq ''      ? P '=' => $_ # make single scalar vals a particle for parsing later
          :                 $_ ;
         } @_;
      }

      while ( my ($col,$val) = each (%where) ) {
         my @bits = upk($val);
         foreach my $bit (@bits) {
            my ($q,@b) = ref($bit)
                       ?  $bit->render($col)
                       : {WTF => $bit} ;

            push @query, $q;
            push @bind, flat(@b);
         }
      }


      return 'WHERE '.join( ' AND ', @query ), @bind;
   }
   sub GROUP {
      my $self = shift;
      return $self->query->has_GROUP ? sprintf q{GROUP BY %s}, COM $self->query->GROUP : '';
   }
   sub ORDER {
      my $self = shift;
      return $self->query->has_ORDER ? sprintf q{ORDER BY %s}, COM $self->query->ORDER : '';
   }
   sub LIMIT {
      my $self = shift;
      return $self->query->has_LIMIT ? sprintf q{LIMIT %d}, $self->query->LIMIT : '';
   }

   sub build {
      my $self = shift;
      my $method = join '_', 'build', lc($self->query->type);
      $self->$method(@_);
   };

   sub build_select {
      my $self = shift;
      my @bind;
      my $query = join ' ', grep{defined && length}
                  sprintf( q{SELECT %s FROM %s}, COM($self->WHAT), COM($self->FROM)),
                  map{ my ($q,@b) = $self->$_;
                       push @bind, @b if @b;
                       $q;
                     } qw{JOIN WHERE GROUP ORDER LIMIT };
    
      return ($query, \@bind); 
   };
   

}; 

BEGIN {
   package Util::DB::QueryBuilder::Query;
   use Moose;
   use Sub::Identify qw{sub_name};

   # DSL : { attr_name => isa_type,
   #   '!required_attr'=> [isa_type => default],
   #       };

   my $attr = { WHAT  => [ArrayRef => ['*']],
              '!FROM' => ArrayRef => 
                JOIN  => HashRef  => 
                WHERE => HashRef  =>
                GROUP => ArrayRef => 
                ORDER => ArrayRef => 
                LIMIT => Int      => 

                type  => [Str     => 'SELECT'],
              };

   my @chainable_attrs;

   for my $name ( keys %$attr ) {
      my ($type,$default) = ref($attr->{$name}) ? @{$attr->{$name}} : $attr->{$name};
      my $required = $name =~ s/^!//;
      push @chainable_attrs, $name if uc($name) eq $name; # only push all upper attrs to chainable
      my $def = {
         is => 'rw',
         isa => $type,
         clearer => qq{clear_$name},
         predicate => qq{has_$name},
      };
      if ( defined $default ) {
         $def->{default} = ref($default) ? sub{$default} : $default;
      }
      $def->{auto_deref} = 1 if $type =~ m/Ref/; # auto_deref if a ref
      has $name => %$def ;
   }
   # allow for chains to be made for all the UPPERCASE attrs ONLY!!!
   around \@chainable_attrs => sub{
      my $next = shift;
      my $self = shift;
      my $rv   = $self->$next(@_);
      return scalar(@_) ? $self : $rv ; # allow for chains if in 'setter' mode
   };

   # 'coerce' lists => HashRef if we were passed anything
   around [qw{JOIN WHERE}] => sub{
      my $next = shift;
      my $self = shift;
      scalar(@_) ? $self->$next(scalar(@_) > 1 ? {@_} : ref($_[0]) eq 'HASH' ? $_[0] : {$_[0] => undef} ) 
                 : %{$self->$next}; # deref
   };

   # 'coerce' lists => ArrayRef if we were passed anything
   around [qw{WHAT FROM GROUP ORDER}] => sub{
      my $next = shift;
      my $self = shift;
      scalar(@_) ? $self->$next(scalar(@_) > 1 ? \@_ : ref($_[0]) eq 'ARRAY' ? $_[0] : [$_[0]] )
                 : @{$self->$next}; #deref
   };

   sub build { Util::DB::QueryBuilder::Builder->new(query => shift)->build(@_); }
      
      
      

}

#---------------------------------------------------------------------------
#  QUERY TYPES
#---------------------------------------------------------------------------
sub SELECT {
   my $q = Util::DB::QueryBuilder::Query->new;
   $q->WHAT(@_) if @_;
   return $q;
};


#---------------------------------------------------------------------------
#  SYNTAX HELPERS
#---------------------------------------------------------------------------
sub _particle{ Util::DB::QueryBuilder::Particle->new(op => shift, value => shift) };
sub gt  ($) {_particle('>' , shift)}
sub gte ($) {_particle('>=', shift)}

sub lt  ($) {_particle('<' , shift)}
sub lte ($) {_particle('<=', shift)} 

sub _set{ Util::DB::QueryBuilder::Set->new( joiner => shift, value => \@_)}
sub OR  {_set(OR  => @_)}
sub AND {_set(AND => @_)}



1;

