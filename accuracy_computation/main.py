import numpy as np
import matplotlib.pyplot as plt
from matplotlib.ticker import PercentFormatter

orig_weights   = np.load("orig_BERT.npy")
pruned_weights = np.load("pruned_BERT.npy")

def mymatmul(W, acts):
    m = len(W)
    n = len(W[0])
    y = [0 for _ in range(m)]
    for i in range(m):
        total = 0
        for j in range(int(n/2)):
            if W[i][j*2] > W[i][j*2+1]:
                total += W[i][2*j] * acts[2*j]
            else:
                total += W[i][2*j+1] * acts[2*j+1]
                
        y[i] = total

    return y


def percent_difference_stats(A, B):
    pct_diff = (np.abs(A - B) / ((np.abs(A) + np.abs(B)) / 2)) * 100
    flat = pct_diff.flatten()
    median = np.median(flat)
    p25 = np.percentile(flat, 25)
    p75 = np.percentile(flat, 75)

    return median, p25, p75, pct_diff


medians = []
p25s = []
p75s = []
for i in range(20):
    print(i)
    example_acts_mat = np.load(f"acts_BERT_{i}.npy")[0]

    p50sum = 0
    p25sum = 0
    p75sum = 0
    # for example_acts_vec in example_acts_mat:
    for example_acts_vec in example_acts_mat[:1]:
        print(orig_weights.shape, example_acts_vec.shape)

        orig_res = np.matmul(orig_weights.T, example_acts_vec)
        merge_res = mymatmul(pruned_weights.T, example_acts_vec)

        p50, p25, p75, _ = percent_difference_stats(orig_res, merge_res)
        p50sum += p50
        p25sum += p25
        p75sum += p75

    # p50sum /= len(example_acts_mat)
    # p25sum /= len(example_acts_mat)
    # p75sum /= len(example_acts_mat)
    medians.append(p50sum)
    p25s.append(p25sum)
    p75s.append(p75sum)
    print(p50sum)

medians = np.array(medians)
p25s = np.array(p25s)
p75s = np.array(p75s)

yerr_low = medians - p25s
yerr_upp = p75s - medians 
yerr = np.vstack([yerr_low, yerr_upp])

plt.figure(figsize=(8,5))
plt.errorbar(np.arange(len(medians)), medians, yerr=yerr, fmt='r-x', capsize=5)
plt.ylim(150,250)
plt.gca().yaxis.set_major_formatter(PercentFormatter())
plt.xlabel("Run")
plt.ylabel("% difference")
plt.title("Median % diff of sparse packed multiplication and INT16 with 25/75 percentiles")
plt.show()
