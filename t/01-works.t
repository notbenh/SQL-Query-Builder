#!/usr/bin/perl;

use strict;
use warnings;

use Test::Most qw{no_plan };
#use SQL::Query::Builder qw{:all};
use SQL::Query::Builder;
use Util::Log;

BEGIN { print qq{\n} for 1..10};


#---------------------------------------------------------------------------
#  DLS
#---------------------------------------------------------------------------
isa_ok
   JOIN(table => 'col'),
   q{SQL::Query::Builder::Query::Part::JOIN},
   q{[DSL] JOIN}
;
isa_ok
   LJOIN(table => 'col'),
   q{SQL::Query::Builder::Query::Part::JOIN},
   q{[DSL] LJOIN}
;
is LJOIN(table => 'col')->type, 'LEFT', q{[DSL] LJOIN sets type to 'LEFT'};
isa_ok
   SELECT->FROM('table'),
   q{SQL::Query::Builder::Query::Select},
   q{[DSL] SELECT}
;


#---------------------------------------------------------------------------
#  BASIC QUERY
#---------------------------------------------------------------------------
=pod
eq_or_diff
   [SELECT->FROM('table')->build],
   [q{SELECT * FROM table},[]],
   q{SELECT FROM}
;

eq_or_diff
   [SELECT->FROM('table')->WHERE(col => 12)->GROUP(qw{kitten cute})->LIMIT(1)->build],
   [q{SELECT * FROM table WHERE `col` = ? GROUP BY kitten, cute LIMIT 1}, [12] ],
   q{basic query works}
;


#---------------------------------------------------------------------------
#  WHAT SYNTAX
#---------------------------------------------------------------------------
eq_or_diff
   [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => 12)->GROUP(qw{kitten cute})->LIMIT(1)->build],
   [SELECT(qw{this that})->FROM(qw{here there})->WHERE(col => 12)->GROUP(qw{kitten cute})->LIMIT(1)->build],
   q{checking both types of WHAT syntax}
;


#---------------------------------------------------------------------------
#  WHERE SYNTAX
#---------------------------------------------------------------------------
=cut
eq_or_diff
   [SELECT->FROM(qw{table})->WHERE(col => GT 12)->build],
   [q{SELECT * FROM table WHERE (`col` > ?)},[12]],
   q{GT expands correctly},
;
eq_or_diff
   [SELECT->FROM(qw{table})->WHERE(col => GTE 12, col => LTE 15)->build],
   [q{SELECT * FROM table WHERE (`col` > ? AND `col` < ?)},[12, 15]],
   q{GT expands correctly},
;
__END__
eq_or_diff
   [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => {'>' => 12})->build],
   [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => GT 12)->build],
   q{do particles work the same as the old hash syntax},
;
eq_or_diff
   [SELECT->FROM(qw{table})->WHERE(col => { '>' => 12, '<' => 15} )->build],
   [q{SELECT * FROM table WHERE (`col` > ? AND `col` < ?)},[12, 15]],
   q{old {} => AND notation still works},
;
eq_or_diff
   [SELECT->FROM(q{table})->WHERE(col => {'>' => 12, '<' => 15})->build],
   [SELECT->FROM(q{table})->WHERE(col => AND [GT 12, LT 15])->build],
   q{Multiple hash is an implied AND set},
;

eq_or_diff
   [SELECT->FROM('table')->WHERE(col=>OR[1..3])->build],
   [q{SELECT * FROM table WHERE (`col` = ? OR `col` = ? OR `col` = ?)},[1..3]],
   q{ArrayRef is an implied OR block}
;
eq_or_diff
   [SELECT->FROM('table')->WHERE(col=>[1..3])->build],
   [q{SELECT * FROM table WHERE (`col` = ? OR `col` = ? OR `col` = ?)},[1..3]],
   q{ArrayRef is an implied OR block}
;
TODO: {
   local $TODO = q{IN syntax not current supported};
eq_or_diff
   [SELECT->FROM('table')->WHERE(col=>IN[1..3])->build],
   [q{SELECT * FROM table WHERE `col` IN (?,?,?)},[1..3]],
   q{IN syntax}
;
};

__END__
eq_or_diff
   [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => {'>' => 12})->build],
   [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => GT 12)->build],
   q{do particles work the same as the old hash syntax},
;


eq_or_diff
   [SELECT->FROM(q{table})->WHERE(col => {'>' => 12, '<' => 15})->build],
   [SELECT->FROM(q{table})->WHERE(col => AND[GT 12, LT 15])->build],
   q{Multiple hash is an implied AND set},
;

TODO: {
   local $TODO = q{Subselect is not currently supported};
eq_or_diff
   [SELECT
    ->FROM('db.table')
    ->WHERE(col => SELECT('id')
                   ->FROM('db.table')
                   ->WHERE(val => LT 12)
           )->build],
   [q{SELECT * FROM db.table WHERE col = (SELECT id FROM db.table WHERE val >= ?)},[12]],
   q{can do subselects}
;

eq_or_diff
   [SELECT
    ->FROM('db.table')
    ->WHERE(col => [ SELECT('id')
                     ->FROM('db.table')
                     ->WHERE(val => LT 12)
                     ->LIMIT(1),
                     SELECT('id')
                     ->FROM('db.table')
                     ->WHERE(val => GT 12)
                     ->LIMIT(1),
                   ],
           )->build],
   [q{SELECT * FROM db.table WHERE ( col = (SELECT id FROM db.table WHERE val =< ?) OR (SELECT id FROM db.table WHERE val >= ?) ) },[12,12]],
   q{can do IN (subselects,subselect)}
;
};

TODO: {
   local $TODO = q{sets currently do not yet self unpack, currently sets assume to contain only particles};
eq_or_diff
   [SELECT->FROM('table')->WHERE(''=>OR[col => 12, val => 15])->build],
   [q{SELECT * FROM table WHERE (`col` = ? OR `val` = ?)},[12,15]],
   q{basic OR syntax}
;
};




#---------------------------------------------------------------------------
#  JOINS
#---------------------------------------------------------------------------
TODO: {
   local $TODO = q{JOINs have not yet been worked out at all};
eq_or_diff
   [SELECT->FROM('table T1', JOIN 'table T2' => 'col' )->WHERE('T1.col' => GT 12)->build],
   [q{SELECT * FROM table T1 JOIN table T2 USING (`col`) WHERE (`col` = ? OR `val` = ?)},[12,15]],
   q{JOIN USING}
;
eq_or_diff
   [SELECT->FROM('table T1', LJOIN 'table T2' => {'T1.col' => 'T2.col', 'T1.val', 'kitten'} )->WHERE('T1.col' => GT 12)->build],
   [q{SELECT * FROM table T1 JOIN table T2 USING (`col`) WHERE (`col` = ? OR `val` = ?)},[12,15]],
   q{JOIN USING}
;

};


#---------------------------------------------------------------------------
#  DBI syntax
#---------------------------------------------------------------------------
TODO: {
   local $TODO = q{because build does not work yet in all cases this will not completely work yet};

eq_or_diff
   [SELECT->FROM('table')->WHERE(col => 13)->dbi(Slice=>{})],
   [q{SELECT * FROM table WHERE `col` = ?},{Slice=>{}},13],
   q{yup that looks about right},
;

};
