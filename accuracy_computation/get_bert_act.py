# !!!! DISCLAIMER: NOT MY CODE !!!!!
import torch
from transformers import BertModel, BertTokenizer
import numpy as np

def collect_ffn_activations(model, tokenizer, texts):
    """
    Runs a list of input texts through BERT and collects activation matrices
    from the first FFN layer.
    """
    ffn_layer = model.encoder.layer[0].intermediate.dense

    activations = []

    # Hook storage
    def capture_activation(module, input, output):
        activations.append(output.detach().clone())

    # Register the hook one time
    hook = ffn_layer.register_forward_hook(capture_activation)

    # Run all texts
    with torch.no_grad():
        for text in texts:
            inputs = tokenizer(text, return_tensors="pt")
            model(**inputs)

    # Remove hook
    hook.remove()

    return activations


# -----------------------------
# Example Usage
# -----------------------------

# Load model + tokenizer
model = BertModel.from_pretrained("bert-base-uncased")
tokenizer = BertTokenizer.from_pretrained("bert-base-uncased")

# Number of activation matrices you want
N = 100

# Example generated sentences (replace with your dataset)
texts = [f"This is example sentence number {i}." for i in range(N)]

# Collect N activation matrices
activation_matrices = collect_ffn_activations(model, tokenizer, texts)

# Display results
for i, act in enumerate(activation_matrices):
    print(f"Activation #{i} shape:", act.shape)
    np.save(f"acts_BERT_{i}.npy", act)
