select * from hackernews hn
inner join lobsters lo

where strftime('%s',hn.created_time) = strftime('%s', lo.created_time)
and hn.url=lo.url;
