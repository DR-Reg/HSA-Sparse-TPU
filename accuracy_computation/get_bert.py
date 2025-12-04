
#---------------------------------------------------
#--- !!! DISCLAIMER: THIS SCRIPT IS NOT MINE !!! ---
#---------------------------------------------------

import torch
from torch import nn
import torch.nn.functional as F
from transformers import BertModel, BertConfig
import numpy as np

# Load pre-trained BERT model (or any model variant)
model = BertModel.from_pretrained('bert-base-uncased')

# Accessing the first FFN layer in BERT (typically located in each transformer block)
# We'll target the first layer of the first encoder block
ffn_layer = model.encoder.layer[0].intermediate.dense

# Step 1: Extract Weights
weights = ffn_layer.weight.data.clone()

# Step 2: Quantize Weights to 16-bit Integers
# First, we scale the weights to fit into the range of 16-bit integers (-32768 to 32767)
min_val = weights.min()
max_val = weights.max()
scaled_weights = 2 * (weights - min_val) / (max_val - min_val) - 1  # scale to [-1, 1]

# Now quantize to 16-bit integer range
quantized_weights = (scaled_weights * 32767).round().to(torch.int16)

# Step 3: Prune 50% of the weights (based on magnitude)
# We can prune by setting the smallest 50% of weights to 0 (magnitude-based pruning)

# Convert weights to a 1D array to easily sort them by magnitude
flattened_weights = quantized_weights.flatten()
# Calculate magnitude (absolute value)
weight_magnitudes = flattened_weights.abs()

# Find the threshold for pruning (50% smallest values)
threshold = torch.kthvalue(weight_magnitudes, int(flattened_weights.numel() // 2)).values.item()

# Prune weights: Set weights smaller than the threshold to 0
pruned_weights = torch.where(weight_magnitudes >= threshold, flattened_weights, torch.tensor(0, dtype=torch.int16))

# Reshape the pruned weights back to the original shape of the weight matrix
pruned_weights = pruned_weights.view(quantized_weights.shape)

# Step 4: Convert the pruned quantized weights back to float32
pruned_weights_float = pruned_weights.to(torch.float32)

# Update the first FFN layer with the pruned, quantized (converted to float) weights
ffn_layer.weight.data = pruned_weights_float

# Step 5: Verify and Output the Pruned, Quantized Weights
# print(f"Original Weights (first FFN layer):\n{weights}")
# print(f"Quantized Weights (16-bit integers):\n{quantized_weights}")
# print(f"Pruned Weights (after 50% pruning):\n{pruned_weights_float}")

# Optionally, save the pruned model if needed
# model.save_pretrained('pruned_bert')
np.save("pruned_BERT.npy", pruned_weights)
np.save("orig_BERT.npy", weights)

