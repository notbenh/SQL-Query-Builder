#!/usr/bin/perl;

use strict;
use warnings;

use Test::Most qw{no_plan };
use SQL::Query::Builder qw{:all};

BEGIN { print qq{\n} for 1..10};

#---------------------------------------------------------------------------
#  BASICS
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


eq_or_diff
   [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => 12)->GROUP(qw{kitten cute})->LIMIT(1)->build],
   [SELECT(qw{this that})->FROM(qw{here there})->WHERE(col => 12)->GROUP(qw{kitten cute})->LIMIT(1)->build],
   q{checking both types of WHAT syntax}
;

#---------------------------------------------------------------------------
#  WHERE SYNTAX
#---------------------------------------------------------------------------
TODO: {
   local $TODO = q{IN syntax not current supported};
eq_or_diff
   [SELECT->FROM('table')->WHERE(col=>[1..3])->build],
   [q{SELECT * FROM table WHERE `col` IN (?,?,?)},[1..3]],
   q{IN syntax}
;
};

eq_or_diff
   [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => {'>' => 12})->build],
   [SELECT->WHAT(qw{this that})->FROM(qw{here there})->WHERE(col => gt 12)->build],
   q{do particles work the same as the old hash syntax},
;


eq_or_diff
   [SELECT->FROM(q{table})->WHERE(col => {'>' => 12, '<' => 15})->build],
   [SELECT->FROM(q{table})->WHERE(col => AND(gt 12, lt 15))->build],
   q{Multiple hash is an implied AND set},
;

TODO: {
   local $TODO = q{Subselect is not currently supported};
eq_or_diff
   [SELECT
    ->FROM('db.table')
    ->WHERE(col => SELECT('id')
                   ->FROM('db.table')
                   ->WHERE(val => lt 12)
           )->build],
   [q{SELECT * FROM db.table WHERE col => (SELECT id FROM db.table WHERE val >= ?)},[12]],
   q{can do subselects}
;

eq_or_diff
   [SELECT
    ->FROM('db.table')
    ->WHERE(col => [ SELECT('id')
                     ->FROM('db.table')
                     ->WHERE(val => lt 12)
                     ->LIMIT(1),
                     SELECT('id')
                     ->FROM('db.table')
                     ->WHERE(val => gt 12)
                     ->LIMIT(1),
                   ],
           )->build],
   [q{SELECT * FROM db.table WHERE col => (SELECT id FROM db.table WHERE val >= ?)},[12]],
   q{can do IN (subselects,subselect)}
;
};

TODO: {
   local $TODO = q{sets currently do not yet self unpack, currently sets assume to contain only particles};
eq_or_diff
   [SELECT->FROM('table')->WHERE(''=>OR(col => 12, val => 15))->build],
   [q{SELECT * FROM table WHERE (`col` = ? OR `val` = ?)},[12,15]],
   q{basic OR syntax}
;
};




