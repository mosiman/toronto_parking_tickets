
# 2016 Toronto Parking Ticket Data Analysis

The City of Toronto has a large selection of datasets that it releases, called the [Open Data Catalogue](https://www.toronto.ca/city-government/data-research-maps/open-data/open-data-catalogue/). You can find the current dataset there. 

I was born and raised in Toronto, but I only recently got my license during the past few years I spent in Waterloo. When I come down to visit my parents, I often park my car on the street overnight, only to find that I've woken up 10 minutes past 8:00 A.M. with a ticket on my dash! I thought, "If I accidently leave my car without paying for parking for $t$ minutes, what's the probability that I get a ticket?"

Last summer I took a course called [Stat 333: Applied Probability](http://www.ucalendar.uwaterloo.ca/1819/COURSE/course-STAT.html#STAT333) and I enjoyed it a lot. The course touched on Markovian processes, and Queueing Theory (at least, those were the parts that caught my attention most!), so it was relatively fresh in my mind that the arrival of parking enforcement police follows something like a [Poisson process](https://en.wikipedia.org/wiki/Poisson_point_process)

And thus, this project was born! I usually do my programming in Python, but I've recently started using Julia, which admittedly has an underwhelming ecosystem, but I think it has great potential. I've grown to love the syntax, and I definitely prefer the non-object-oriented multiple-dispatch approach. 

Julia was used for much of the exploring, data munching, etc. My website already has a backend in Python (Flask), so that's how I'm serving the application to you all. 

I'll have some more details in a complementary blog post, including how the data was crunched and how it needs to be improved. 

Without further ado, let's look at some graphs!


## Hourly Frequency

Let's tally up how many tickets are issued per hour:


As we can see, the quietest hour is 5 A.M., but it's fairly busy elsewhere. 

The maximum is right at noon. On a circular histogram, we notice a peculiar jump in activity at midnight, which I suspect has to do with neighbourhood permits. 

It's a bit crude, but I was unhappy with the lack of a circular histogram-type option in the Plots.jl library.

On a day-by-day basis, there is slightly less activity on Monday and Saturday compared to Tuesday through Friday, but it is especially low on Sunday. 


![Hourly distribution of infractions by day. Saturdays and sundays have a markedly different distribution than the weekdays.](../hourly_by_day.gif)

On a seasonal note, the distribution by hour is mostly the same:

![](../hourly_by_season.gif)

## Street Segment analysis

Per _street segment_, the distribution of days out of the year tickets have been issued looks like

![](../streetseg_freq_by_day.png)

We can see that most street segments only have been visited between 2-37 days out of the year, with the minimum being 1 visit and the maximum being 366 (2016 was a leap year!), i.e., every day. The median number of visits was 8, i.e., half of the street segments had over (or equal to) 8 days visited out of the year, and the other half had under 8 days visited out of the year.

Assuming that there is usually an infraction waiting to be ticketed at all times (which granted is not a great assumption on less busy streets), we can use the difference between one cluster of parking tickets and the next as a proxy for how often a parking enforcement officer visits. 

For example, if on a particular street, tickets are made from 10:15 a.m. to 10:20 a.m., and the next ticket comes at 11:20 a.m., the _interarrival time_ is 1 hour. For this analysis, any gap greater than 15 minutes counts as a new arrival of a parking enforcement officer. 

Assuming that at in any interval of time:
- There is only one parking enforcement officer (which seems okay, otherwise it would be quite a waste of resources)
- Future arrivals don't depend on past arrivals (without more information on how the city distributes its parking enforcement officers, I think this is a decent assumption)
- Future arrivals all have the same distribution, which again is an assumption I will make without further information,

the process is a Poisson process. That means that the distribution of interarrival times should [follow an exponential distribution](https://en.wikipedia.org/wiki/Exponential_distribution#Occurrence_of_events). Is this the case? Let's find out.

As an example, let's look at a fairly busy street downtown. To be precise, the streetsegment in question has had 707 tickets in 2016 over 293 days out of the year. This puts the streetsegment squarely in "outlier" territory, in terms of number of tickets given. However, that means we can make better inferences on this street. 

![](../quarterly_interarrivals.png)

We fit the interarrival data with an exponential distribution with mean $\theta = 920.681 \cdots $.

It looks like a good fit, and a QQ plot agrees. Furthermore, an approximate one sample [Kolmogorov-Smirnov test](https://en.wikipedia.org/wiki/Kolmogorov%E2%80%93Smirnov_test) rejects it's null hypothesis under a 95% confidence window, i.e., it's very likely that these interarrival times were sampled from an exponential distribution.

![](../QQ_quarterly_interarrival_exponential.png)

This data suggests that for this particular street segment, parking enforcement interarrival times are on average 920 minutes apart (around 15 hours). 

However, for all the streetsegments with more than 300 infractions (the analysis is significantly less fruitful with less observations), the distribution of $\theta$ is quite wide, which suggests that there is no global interarrival distribution that all street segments follow. Furthermore, most of these streetsegments don't pass the KS exponentiality test. Out of 1721 street segments with over 300 infractions, only 357 passed the Kolmogorov-Smirnov test, so only about 20% of these streets pass the KS test under a 95% confidence interval. Note that these numbers are actually need to be corrected, as the KS test has a different distribution with estimated parameters (like we have done here). More on this in the blog post, but the gist is that HypothesisTests.jl doesn't have a Lilliefors test (maybe I'll make that pull request?). Despite the low passing rate for under the KS test, I have little reason to suspect that most streets are visited under some other distribution, and that the low passing rate is due to bad segmentation of the streetsegments.

![](../theta_distr.png)

If one interprets the data blindly, one would think that most streets only get ticketed somewhere between $0.5\%$ and $10\%$. Of course, how a street segment is defined changes these statistics quite a bit. In a nutshell, a reverse geocode of a lat/lng coordinate is run through a Nominatim server at a zoom level of 16. This data isn't all that consistent, i.e., some street segments are very short, which skews the results in favor of longer interarrival times. 

## Conclusion

As I mentioned before, there are many things that could be done in order to optimize the analysis, extend it, etc., as well making it more statistically correct. However, I think this analysis is a decent overview of the data and how we can infer the behaviour (interarrival times) of parking enforcement officers.

That's it for now! I enjoyed this project a lot and hope to do more in the future (wink wink employers, I'm looking for internships or a post-graduation job!). For another cool analysis from a different perspective, check out [Anthony Ionno's blog post](https://ionnoant.github.io/posts/2018/01/blog-post-5/)

