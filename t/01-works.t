#!/usr/bin/perl;

use strict;
use warnings;

use Test::Most qw{no_plan };
use Util::DB::QueryBuilder qw{:all};

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
eq_or_diff
   [SELECT->FROM('table')->WHERE(col=>[1..3])->build],
   [q{SELECT * FROM table WHERE `col` IN (?,?,?)},[1..3]],
   q{IN syntax}
;

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

__END__
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
__END__




eq_or_diff
   [SELECT->FROM('table')->WHERE(OR(col => 12, val => 15))->build],
   [q{SELECT * FROM table WHERE (`col` = ? OR `val` = ?)},[12,15]],
   q{basic OR syntax}
;











__END__
#-----------------------------------------------------------------
#  
#-----------------------------------------------------------------
eq_or_diff (
   soq(1,2),
   '?,?',
   q{soq},
);

eq_or_diff (
   soq([1,2]),
   '?,?',
   q{soq},
);


sub test_build {
   my ($opts,$sql,$val, $note) = @_;

   eq_or_diff (
     [ build_query_from_hash( %$opts ) ],
     [ $sql, $val ],
     $note,
   ); 
}


test_build(
   { query => q{SELECT * FROM current.stock}, 
     where => {'LENGTH(title_key)'  => { '>' => 0},
               'LENGTH(author_key)' => { '>' => 0},
              },
     limit => 10, 
   },
   q{SELECT * FROM current.stock WHERE LENGTH(title_key) > ? AND LENGTH(author_key) > ? LIMIT 10},
   [0,0],
   q{TESTING THE FUZZY BANDAID that catches bad title/author keys}, 
);

test_build(
   { query => q{SELECT * FROM current.stock}, 
     where => {copyright => [1979,1980,1981],
               binding   => ['TRADE PAPER','MASS MARKET'] 
              },
     limit => 10, 
   },
   q{SELECT * FROM current.stock WHERE `binding` IN (?,?) AND `copyright` IN (?,?,?) LIMIT 10},
   ['TRADE PAPER','MASS MARKET',1979,1980,1981],
   q{build query from hash },
);

test_build(
   { query => q{SELECT * FROM current.stock}, 
     where => {copyright => undef,
               binding   => ['TRADE PAPER','MASS MARKET'] 
              },
     limit => 10, 
   },
   q{SELECT * FROM current.stock WHERE `binding` IN (?,?) AND `copyright` IS NULL LIMIT 10},
   ['TRADE PAPER','MASS MARKET'],
   q{build query from hash with blanks},
);

test_build(
   { query => q{SELECT * FROM table}, 
     where => { num => { '>' => {raw => 'INTERVAL ? MONTHS', val => 12}}},
   },
   q{SELECT * FROM table WHERE `num` > INTERVAL ? MONTHS},
   [12],
   q{raw and value insertion},
);

test_build(
   { query => q{SELECT * FROM table}, 
     where => { num => { '>' => 1,
                         '<' => 100,
                       }
              },
   },
   q{SELECT * FROM table WHERE `num` > ? AND `num` < ?},
   [1,100],
   q{multiple op overrides insertion},
);

test_build(
   { query => q{SELECT * FROM table}, 
     where => { num => { 'NOT' => [1,2,3,4],
                         '<' => 100,
                       }
              },
   },
   q{SELECT * FROM table WHERE `num` NOT IN (?,?,?,?) AND `num` < ?},
   [1,2,3,4,100],
   q{multiple op overrides insertion},
);

test_build(
   { query => q{SELECT * FROM table},
     where => { '' => { '' => {raw => q{ ( (SUBSELECT ?) - (SUBSELECT ?) ) }, 
                               val => [1,2],
                              }}},
   },
   q{SELECT * FROM table WHERE ( (SUBSELECT ?) - (SUBSELECT ?) )},
   [1,2],
   q{raw and value can also be faked out with null keys},
);


#---------------------------------------------------------------------------
#  SQL INJECTION PROTECTION
#---------------------------------------------------------------------------
test_build(
   { query => q{SELECT * FROM table},
     where => { q{"";drop database X;SELECT * FROM table WHERE something} => 1 },
   },
   q{SELECT * FROM table WHERE `""\;dropdatabaseX\;SELECT*FROMtableWHEREsomething` = ?},
   [1],
   q{SQL INJECTION protection},
);



#---------------------------------------------------------------------------
#  Checking for long queries
#---------------------------------------------------------------------------
use DBHost;
my $d = _dbiconnect('current');
lives_ok {
   do_select( $d,
      query => q{select * from current.stock},
      where => { isbn => '9780394858180' },
      timeout => 10, 
   )
} q{when you have a short query all is good} ;

dies_ok {
   do_select( $d,
      query => q{select * from current.stock},
      timeout => 1, 
   )
} q{and when you have something that runs past the timeout, you die};


#---------------------------------------------------------------------------
#  what happens when you pass the wrong type via where?
#-----------------------------------------------------ld_query_from_hash( 
dies_ok 
   {build_query_from_hash( 
      query => q{SELECT * FROM current.stock},
      where => [1,2,3],
      expire=> 10,
   )}
   q{garbage in => death}
;



#---------------------------------------------------------------------------
#  Quote + function weirdness
#---------------------------------------------------------------------------

test_build(
   { query => q{SELECT isbn, CONCAT(faux_order_id, status_time) AS faux_key  FROM obb.pos_sales},
     where => { 'CONCAT(faux_order_id, status_time)' => [qw{1094906012009-07-13 124101072009-07-03 1536109012009-06-16}],
                faux_order_id => { '>' => 0},
                status_time   => { '>='=> {raw => q{now() - INTERVAL ? MONTH}, val => 2}},
              },
     group => [qw{isbn faux_key}],
   },
   q{SELECT isbn, CONCAT(faux_order_id, status_time) AS faux_key FROM obb.pos_sales WHERE CONCAT(faux_order_id, status_time) IN (?,?,?) AND `faux_order_id` > ? AND `status_time` >= now() - INTERVAL ? MONTH GROUP BY isbn, faux_key},
   [qw{1094906012009-07-13 124101072009-07-03 1536109012009-06-16},0,2],
   q{we should escape the internals of functions},
);

test_build(
   { query => q{SELECT * FROM table},
     where => { 'DATE_SUB(CURDATE(),INTERVAL 30 DAY)' => 
                  { '<=' => 'date_col'},
              },
   },
   q{SELECT * FROM table WHERE DATE_SUB(CURDATE(),INTERVAL 30 DAY) <= ?},
   [qw{date_col}],
   q{INTERVAL example},
);

test_build(
   { query => q{SELECT * FROM table},
     where => { 'NOW()' => 
                  { '>' => 'some_date'},
              },
     limit => 1,
   },
   q{SELECT * FROM table WHERE NOW() > ? LIMIT 1},
   ['some_date'],
   q{NOW() example},
);

test_build(
   { query => q{SELECT * FROM table},
     where => { 'CONCAT(...) bad shit ()' => 42 },
     limit => 1,
   },
   q{SELECT * FROM table WHERE CONCAT(``.``.``.`)badshit(`) = ? LIMIT 1},
   [42],
   q{BAD() example},
);

test_build(
   { query => q{SELECT * FROM table},
     where => { 'CONCAT(...) bad shit () extra fluff' => 42 },
     limit => 1,
   },
   q{SELECT * FROM table WHERE CONCAT(``.``.``.`)badshit(`)`extrafluff` = ? LIMIT 1},
   [42],
   q{BAD()xx example},
);




#---------------------------------------------------------------------------
#  NULL
#---------------------------------------------------------------------------
test_build(
   { query => q{SELECT * FROM table},
     where => { col => undef},
   },
   q{SELECT * FROM table WHERE `col` IS NULL},
   [],
   q{NULL example},
);

#---------------------------------------------------------------------------
#  Turn off quoting (SQLSERVER)
#---------------------------------------------------------------------------
test_build(
   { query => q{SELECT * FROM table},
     where => { 'tbl.col' => undef},
     DB_quote => 0,
   },
   q{SELECT * FROM table WHERE tbl.col IS NULL},
   [],
   q{no quote example},
);

#---------------------------------------------------------------------------
#  Comments 
#---------------------------------------------------------------------------
test_build(
   { 'query' => 'SELECT title_key, author_key FROM current.stock',
     'timeout' => '30',
     'skip_cache_check' => 0,
     'expire' => '0',
     'where' => { 'isbn /* test */' => '9780767932622' },
   } ,
    'SELECT title_key, author_key FROM current.stock WHERE `isbn` /* test */ = ?',
   [qw{9780767932622}],
);

#---------------------------------------------------------------------------
#  FORCE OR SYNTAX
#---------------------------------------------------------------------------
test_build(
   { 'query' => 'SELECT * FROM table',
     'timeout' => '30',
     'skip_cache_check' => 0,
     'expire' => '0',
     'where' => { 'isbn /* test */' => '9780767932622' },
   } ,
   q{SELECT * FROM table WHERE `isbn` /* test */ = ?},
   [qw{9780767932622}],
   q{comments work too},
);

#---------------------------------------------------------------------------
#  NULL IN BLOCKS?  
#---------------------------------------------------------------------------
test_build(
   { 'query' => 'SELECT * FROM table',
     'where' => { col_A => 1,
                  col_B => {NOT => [] },
                },
   } ,
   'SELECT * FROM table WHERE `col_A` = ?',
   [1]
   # 'SELECT title_key, author_key FROM current.stock WHERE `isbn` /* test */ = ?',
   #[qw{9780767932622}],
);
test_build(
   { 'query' => 'SELECT * FROM table',
     'where' => { col_A => 1,
                  col_B => {NOT => [100], '' => [101] },
                },
   } ,
   'SELECT * FROM table WHERE `col_A` = ? AND `col_B` IN (?) AND `col_B` NOT IN (?)',
   [1,101,100]
);


#---------------------------------------------------------------------------
#  AND JOIN LIKE BLOCKS
#---------------------------------------------------------------------------
test_build(
   { 'query' => 'SELECT * FROM table',
     'where' => { col => { LIKE => [qw{A B C}] },
                },
   } ,
   q{SELECT * FROM table WHERE `col` LIKE ? AND `col` LIKE ? AND `col` LIKE ?},
   [qw{A B C}],
);












__END__
cant seem to find a good way to test this
#---------------------------------------------------------------------------
#  Check Caching
#---------------------------------------------------------------------------
ok (
   build_query_from_hash( 
      query => q{SELECT * FROM current.stock},
      where => { isbn => 9780345366238  },
      expire=> 10,
   ),
   q{ can build a cached query },
);

use Util::Cache;
my $key = 'Util::DB::Query10_9780345366238_SELECT_*_FROM_current.stock_build_query_from_hash_expire_isbn_query_where';

eq_or_diff (
   cache->get($key),
   [ q{SELECT * FROM current.stock WHERE isbn = ?}, [9780345366238] ],
   q{cache matches},
);



























__END__
eq_or_diff (
   [ build_query_from_hash(
      query => q{SELECT isbn, sales_count FROM table},
      where => {
       slocation => [1,2,3,4,5],
       status => { NOT => [10,11,12,13]},
       class => ['new'],
       squantity => { '>' => 0 },
       sprice => { '>' => 0 },
       status_time => { '>' => { raw => sprintf( q{now() - INTERVAL %d MONTHS}, 10) } },
      }) 
   ],
   [ q{SELECT isbn, sales_count FROM table WHERE slocation IN (?,?,?,?,?) AND status NOT IN (?,?,?,?) AND class IN (?) AND squantity > ? AND sprice > ? AND status_time > now() - INTERVAL 10 MONTHS},
      [10,11,12,13,1,2,3,4,5,'new',0,0]
   ],
   q{now with ops}
);
