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
eq_or_diff
   [SELECT->FROM(qw{table})->WHERE(col => GT 12)->build],
   [q{SELECT * FROM table WHERE `col` > ?},[12]],
   q{GT expands correctly},
;
eq_or_diff
   [SELECT->FROM(qw{table})->WHERE(col => GTE 12, col => LTE 15)->build],
   [q{SELECT * FROM table WHERE (`col` >= ? AND `col` <= ?)},[12, 15]],
   q{GT expands correctly},
;

SKIP: {
      skip q{do I really want to support the old style syntax?}, 5;

   TODO: {
      local $TODO = q{do I really want to support the old style syntax?};
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
         [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => {'>' => 12})->build],
         [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => GT 12)->build],
         q{do particles work the same as the old hash syntax},
      ;


      eq_or_diff
         [SELECT->FROM(q{table})->WHERE(col => {'>' => 12, '<' => 15})->build],
         [SELECT->FROM(q{table})->WHERE(col => AND[GT 12, LT 15])->build],
         q{Multiple hash is an implied AND set},
      ;
   };
};

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
eq_or_diff
   [SELECT->FROM('table')->WHERE(col=>IN[1..3])->build],
   [q{SELECT * FROM table WHERE `col` IN (?,?,?)},[1..3]],
   q{IN syntax}
;

eq_or_diff
   [SELECT
    ->FROM('db.table')
    ->WHERE(col => SELECT('id')
                   ->FROM('db.table')
                   ->WHERE(val => LT 12)
           )->build],
   [q{SELECT * FROM db.table WHERE `col` = (SELECT id FROM db.table WHERE `val` < ?)},[12]],
   q{can do subselects}
;

eq_or_diff
   [SELECT
    ->FROM('db.table')
    ->WHERE(col => [ SELECT('id')
                     ->FROM('db.table')
                     ->WHERE(val => LTE 12),
                     SELECT('id')
                     ->FROM('db.table')
                     ->WHERE(val => GTE 12),
                   ],
           )->build],
   [q{SELECT * FROM db.table WHERE (`col` = (SELECT id FROM db.table WHERE `val` <= ?) OR `col` = (SELECT id FROM db.table WHERE `val` >= ?))},[12,12]],
   q{can do IN (subselects,subselect)}
;

#---------------------------------------------------------------------------
#  LONE SETS
#---------------------------------------------------------------------------
eq_or_diff
   [SELECT->FROM('table')->WHERE(OR{col => 12, val => 15})->build],
   [q{SELECT * FROM table WHERE (`col` = ? OR `val` = ?)},[12,15]],
   q{basic OR syntax}
;
eq_or_diff
   [SELECT->FROM('table')->WHERE(OR{one => 12, val => 15}, col=> 13 )->build],
   [q{SELECT * FROM table WHERE ((`one` = ? OR `val` = ?) AND `col` = ?)},[12,15,13]],
   q{basic OR syntax with extras}
;

#---------------------------------------------------------------------------
#  JOINS
#---------------------------------------------------------------------------
TODO: {
   local $TODO = q{JOINs have not yet been worked out completely, the FROM block still joins with ', ' thus you end up with FROM table, JOIN};
eq_or_diff
   [SELECT->FROM('table T1', JOIN 'table T2' => 'col' )->WHERE('T1.col' => GT 12)->build],
   [q{SELECT * FROM table T1 JOIN table T2 USING (`col`) WHERE `T1`.`col` > ?},[12]],
   q{JOIN USING}
;
eq_or_diff
   [SELECT->FROM('table T1', LJOIN 'table T2' => {'T1.col' => 'T2.col', 'T1.val'=> 'T2.val'} )->WHERE('T1.col' => GT 12)->build],
   [q{SELECT * FROM table T1 LEFT JOIN table T2 ON (`T1`.`col` = `T2`.`col` AND `T1`.`val` = `T2`.`val`) WHERE `T1`.`col` > ?},[12]],
   q{JOIN USING}
;

};


#---------------------------------------------------------------------------
#  DBI syntax
#---------------------------------------------------------------------------
eq_or_diff
   [SELECT->FROM('table')->WHERE(col => 13)->dbi(Slice=>{})],
   [q{SELECT * FROM table WHERE `col` = ?},{Slice=>{}},13],
   q{yup that looks about right},
;

__END__
ok 1 - [DSL] JOIN isa SQL::Query::Builder::Query::Part::JOIN
ok 2 - [DSL] LJOIN isa SQL::Query::Builder::Query::Part::JOIN
ok 3 - [DSL] LJOIN sets type to 'LEFT'
ok 4 - [DSL] SELECT isa SQL::Query::Builder::Query::Select
ok 5 - SELECT FROM
ok 6 - basic query works
ok 7 - checking both types of WHAT syntax
ok 8 - GT expands correctly
ok 9 - GT expands correctly
ok 10 # skip do I really want to support the old style syntax?
ok 11 # skip do I really want to support the old style syntax?
ok 12 # skip do I really want to support the old style syntax?
ok 13 # skip do I really want to support the old style syntax?
ok 14 # skip do I really want to support the old style syntax?
ok 15 - ArrayRef is an implied OR block
ok 16 - ArrayRef is an implied OR block
ok 17 - IN syntax
ok 18 - can do subselects
ok 19 - can do IN (subselects,subselect)
ok 20 - basic OR syntax
ok 21 - basic OR syntax with extras
not ok 22 - JOIN USING # TODO JOINs have not yet been worked out completely, the FROM block still joins with ', ' thus you end up with FROM table, JOIN
#   Failed (TODO) test 'JOIN USING'
#   at t/01-works.t line 170.
# +----+-------------------------------------------------------------------------------+------------------------------------------------------------------------------+
# | Elt|Got                                                                            |Expected                                                                      |
# +----+-------------------------------------------------------------------------------+------------------------------------------------------------------------------+
# |   0|[                                                                              |[                                                                             |
# *   1|  'SELECT * FROM table T1, JOIN table T2 USING (`col`) WHERE `T1`.`col` > ?',  |  'SELECT * FROM table T1 JOIN table T2 USING (`col`) WHERE `T1`.`col` > ?',  *
# |   2|  [                                                                            |  [                                                                           |
# |   3|    12                                                                         |    12                                                                        |
# |   4|  ]                                                                            |  ]                                                                           |
# |   5|]                                                                              |]                                                                             |
# +----+-------------------------------------------------------------------------------+------------------------------------------------------------------------------+
not ok 23 - JOIN USING # TODO JOINs have not yet been worked out completely, the FROM block still joins with ', ' thus you end up with FROM table, JOIN
#   Failed (TODO) test 'JOIN USING'
#   at t/01-works.t line 175.
# +----+-------------------------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------------------------+
# | Elt|Got                                                                                                                            |Expected                                                                                                                      |
# +----+-------------------------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------------------------+
# |   0|[                                                                                                                              |[                                                                                                                             |
# *   1|  'SELECT * FROM table T1, LEFT JOIN table T2 ON (`T1`.`col` = `T2`.`col` AND `T1`.`val` = `T2`.`val`) WHERE `T1`.`col` > ?',  |  'SELECT * FROM table T1 LEFT JOIN table T2 ON (`T1`.`col` = `T2`.`col` AND `T1`.`val` = `T2`.`val`) WHERE `T1`.`col` > ?',  *
# |   2|  [                                                                                                                            |  [                                                                                                                           |
# |   3|    12                                                                                                                         |    12                                                                                                                        |
# |   4|  ]                                                                                                                            |  ]                                                                                                                           |
# |   5|]                                                                                                                              |]                                                                                                                             |
# +----+-------------------------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------------------------+
ok 24 - yup that looks about right
1..24

