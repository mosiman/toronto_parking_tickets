SQLite.query(db, sr"insert into test (userid, value) values (:userid, :value)", values = Dict(:userid => 3, :value => 5))

# use SQLite.exec!(db, "BEGIN TRANSACTION") and END TRANSACTION to speed up inserts.

function make_db(dbname, i)
    db = SQLite.DB(string(dbname, "_", i))
    SQLite.query(db,"create table if not exists foo(userid int, value int)")
    return db
end

db_procs = map(x -> make_db("testdb", x), procs())

# multithreaded

@time @sync for i in 1:10000
    @spawn SQLite.query(db_procs[Thread.threadid()], "insert into table foo values (:col1, :col2, ... , :coln)" values = Dict(:col1 => val1, :col2 =>val2, ... , :coln => valn))
end


