---
date: '2025-12-03T06:00:00-05:00'
events: []
events_extracted: true
images: []
original_content: |-
  <div>
  <p>Annu Int Conf IEEE Eng Med Biol Soc. 2025 Jul;2025:1-7. doi: 10.1109/EMBC58623.2025.11252783.</p>
  <p><b>ABSTRACT</b></p>
  <p>This paper details the development of a deep neural network, and an accompanying application, capable of classifying and detecting five target classes important to the deaf and hard-of-hearing: a running faucet, a dripping faucet, a car engine, a car horn, and a fridge alarm. These classes were based on questionnaire results from previous research, which concluded with a long short-term memory (LSTM) model and an augmented self-captured dataset, but fell short of developing a mobile application as originally planned. To make such an application possible, this subsequent research primarily focused on the implementation of a "negative" class to account for the irrelevant sounds, those not part of the target classes, expected in real-world scenarios. The research therefore improved upon the previous results by designing a more capable model, while subsequent development served to embed this model into an application accessible from most mobile phones.The final model achieved an AUC of 0.97 ± 0.01, with a very well-balanced precision and recall, compromising between the conflicting tolerances fit for the critical and benign target classes. This was achieved through a novel approach for fine-tuning the YamNet audio classification model, where its scores - representing the ontology of the AudioSet dataset - were used as query for its embeddings, and an LSTM was used to flatten the resulting frames while retaining temporal information outside the scope of a single frame. To keep the performance overhead minimal, the scores and embeddings were resized using convolutional layers, resulting in a model fit for real-time use on mobile devices. To this end, the model was deployed to the Web using TensorFlow.js, and made available for offline use as a Progressive Web App. However, further research should focus on user testing to ensure the application and underlying model fulfil the needs of the target audience.</p>
  <p>PMID:<a>41336651</a> | DOI:<a>10.1109/EMBC58623.2025.11252783</a></p>
  </div>
original_content_checksum: aeb00cb6e365dd7793723dc5a5a85949f893fe7c
original_markdown_body: |-
  Annu Int Conf IEEE Eng Med Biol Soc. 2025 Jul;2025:1-7. doi: 10.1109/EMBC58623.2025.11252783.

  **ABSTRACT**

  This paper details the development of a deep neural network, and an accompanying application, capable of classifying and detecting five target classes important to the deaf and hard-of-hearing: a running faucet, a dripping faucet, a car engine, a car horn, and a fridge alarm. These classes were based on questionnaire results from previous research, which concluded with a long short-term memory (LSTM) model and an augmented self-captured dataset, but fell short of developing a mobile application as originally planned. To make such an application possible, this subsequent research primarily focused on the implementation of a "negative" class to account for the irrelevant sounds, those not part of the target classes, expected in real-world scenarios. The research therefore improved upon the previous results by designing a more capable model, while subsequent development served to embed this model into an application accessible from most mobile phones.The final model achieved an AUC of 0.97 ± 0.01, with a very well-balanced precision and recall, compromising between the conflicting tolerances fit for the critical and benign target classes. This was achieved through a novel approach for fine-tuning the YamNet audio classification model, where its scores - representing the ontology of the AudioSet dataset - were used as query for its embeddings, and an LSTM was used to flatten the resulting frames while retaining temporal information outside the scope of a single frame. To keep the performance overhead minimal, the scores and embeddings were resized using convolutional layers, resulting in a model fit for real-time use on mobile devices. To this end, the model was deployed to the Web using TensorFlow.js, and made available for offline use as a Progressive Web App. However, further research should focus on user testing to ensure the application and underlying model fulfil the needs of the target audience.

  PMID:41336651 | DOI:10.1109/EMBC58623.2025.11252783
source: Disabilities PubMed
source_url: https://pubmed.ncbi.nlm.nih.gov/41336651/?utm_source=Chrome&utm_medium=rss&utm_campaign=pubmed-2&utm_content=1VMHU6Rqfkbmp1WZiY3ECqj__40TKSFM7lNSANqB9VZOI0iYfd&fc=20251206213128&ff=20251206213308&v=2.18.0.post22+67771e2
summarized: true
title: Developing Accessible Assistive Technology for the Deaf and Hard of Hearing
  by Deploying a Fine-Tuned Deep Neural Network to the Web
topics:
- Disabilities
- Health Care
---

A new deep neural network and mobile application have been developed to assist the deaf and hard-of-hearing community by classifying and detecting five significant sounds: a running faucet, a dripping faucet, a car engine, a car horn, and a fridge alarm. This research builds on prior work that utilized a long short-term memory (LSTM) model and an enhanced self-captured dataset but did not produce a mobile application. The current study introduced a "negative" class to include irrelevant sounds encountered in real-world settings. The refined model achieved an area under the curve (AUC) score of 0.97, balancing precision and recall effectively for critical and benign sounds. A novel approach was taken to fine-tune the YamNet audio classification model, employing convolutional layers to minimize performance overhead for real-time mobile use. The model has been deployed on the Web through TensorFlow.js and is available as a Progressive Web App for offline access. Future research will focus on user testing to ensure the application and model meet the needs of its intended users.
