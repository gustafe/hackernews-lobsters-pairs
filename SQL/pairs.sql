select hn.url,
strftime('%s',lo.created_time)-strftime('%s',hn.created_time) as diff,
hn.id as hn_id,
strftime('%s',hn.created_time) as hn_time,
hn.title as hn_title , hn.submitter as hn_submitter,hn.score as hn_score, hn.comments as hn_comments,
lo.id as lo_id,
strftime('%s',lo.created_time) as lo_time,
lo.title as lo_title, lo.submitter as lo_submitter,lo.score as lo_score, lo.comments as lo_comments
from hackernews hn
inner join lobsters lo
on lo.url = hn.url
where hn.url is not null
order by hn.created_time
