//
//  selection sort
//

#include <stdlib.h>
#include <iostream>
#include <list>

using namespace std;

typedef list <long> llist;

long
my_sort(llist & olist, llist & nlist)
{
    long sum;

    sum = 0;
    while (olist.size() > 0) {
	auto min = olist.begin();

	for (auto it = olist.begin(); it != olist.end(); ++it) {
	    if (*it < *min) {
		min = it;
	    }
	}
	sum += *min;
	nlist.push_back(*min);
	olist.erase(min);
    }

    return sum;
}
