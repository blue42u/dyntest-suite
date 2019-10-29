//
//  selection sort
//

#include <stdlib.h>
#include <iostream>
#include <list>

using namespace std;

typedef list <long> llist;

long my_sort(llist &, llist &);

int main(int argc, char **argv)
{
    llist olist, nlist;
    long n, N, sum;

    N = 50000;

    if (argc > 1) {
	N = atol(argv[1]);
    }

    sum = 0;
    for (n = 1; n <= N; n += 2) {
	olist.push_front(n);
	olist.push_back(n + 1);
	sum += 2 * n + 1;
    }

    cout << "orig list:  " << N << "  " << sum << endl;

    sum = my_sort(olist, nlist);

    cout << "new list:   " << N << "  " << sum << endl;

    return 0;
}
