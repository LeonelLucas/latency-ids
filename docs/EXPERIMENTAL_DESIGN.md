# Experimental design hierarchy

```mermaid
flowchart TB
    DATA["Corrected CICIDS2017<br/>84 predictive attributes"]
    TRAIN["Training: Monday-Wednesday<br/>fit eight classifiers"]
    VALID["Validation: Thursday<br/>threshold sensitivity"]
    TEST["Test: Friday<br/>unseen flows and attack families"]
    PRED["Predictive metrics<br/>1%, 5%, 10%, and 50% prevalence"]

    DATA --> TRAIN
    DATA --> VALID
    DATA --> TEST
    TRAIN --> VALID --> TEST --> PRED

    MODELS["Eight fitted pipelines"]
    HOSTS["Protocol repeated on<br/>Host-LC and Host-SW"]
    PROCESS["12 fresh sequential processes per host"]
    CONDITION["Per process:<br/>8 classifiers x 6 call sizes x 6 fractions<br/>= 288 conditions"]
    CALL["30 timed calls per condition<br/>= 8,640 calls per process"]
    RAW["Per call:<br/>total latency, per-flow latency, throughput"]

    TRAIN --> MODELS --> HOSTS --> PROCESS --> CONDITION --> CALL --> RAW
    TEST -->|"benign and malicious timing pools"| CONDITION

    SUMMARY["Per condition and host:<br/>30 x 12 = 360 calls<br/>median, mean, SD, p95, p99"]
    PAIR["Within each process:<br/>mean of 30 benign calls -<br/>mean of 30 malicious calls"]
    UNIT["Confirmatory unit:<br/>12 paired process differences"]
    REPLICATE["Replicated effect:<br/>corrected significance on both hosts<br/>with the same direction"]

    RAW --> SUMMARY --> PAIR --> UNIT --> REPLICATE
```

## Four levels that must not be conflated

1. **Experimental condition:** one classifier, one call size, one requested
   malicious fraction, and one host.
2. **Timed call:** one invocation of `Pipeline.predict`; there are 30 calls for
   a condition inside each process.
3. **Process run:** a fresh Python runtime that executes all conditions; this is
   the independent block for the class-composition test.
4. **Host:** a physical execution environment on which the full protocol is
   independently reproduced.

The complete call count is:

```text
8 classifiers x 6 call sizes x 6 fractions x 30 calls
x 12 processes x 2 hosts = 207,360 timed calls
```

The confirmatory sample size for one classifier/call-size class comparison is
12, not 360: each process contributes one benign-minus-malicious mean
difference.
