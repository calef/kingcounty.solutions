---
date: '2025-12-09T17:30:37+00:00'
feed_content: |-
  <div>
  <!--[if lt IE 9]><script>document.createElement('video');</script><![endif]--><br>
  <video><source></source><a>https://uw-s3-cdn.s3.us-west-2.amazonaws.com/wp-content/uploads/sites/6/2025/11/14101348/proactive_listening_demo.mp4</a></video>
  </div>
  <p> </p>
  <p><span>Holding a conversation in a crowded room often leads to the frustrating “cocktail party problem,” or the challenge of separating the voices of conversation partners from a hubbub. It’s a mentally taxing situation that can be exacerbated by hearing impairment. </span></p>
  <p><span>As a solution to this common conundrum, researchers at the University of Washington have developed </span><a><span>smart headphones</span></a><span> that proactively isolate all the wearer’s conversation partners in a noisy soundscape. The headphones are powered by an AI model that detects the cadence of a conversation and another model that mutes any voices which don’t follow that pattern, along with other unwanted background noises. The prototype uses off-the-shelf hardware and can identify conversation partners using just two to four seconds of audio.</span></p>
  <p><span>The system’s developers think the technology could one day help users of hearing aids, earbuds and smart glasses to filter their soundscapes without the need to manually direct the AI’s “attention.”</span></p>
  <p><span>The team </span><a><span>presented the technology</span></a><span> Nov. 7 in Suzhou, China at the Conference on Empirical Methods in Natural Language Processing. The underlying code is open-source and </span><a><span>available for download</span></a><span>.</span></p>
  <p><span>“Existing approaches to identifying who the wearer is listening to predominantly involve electrodes implanted in the brain to track attention,” said senior author </span><a><span>Shyam Gollakota</span></a><span>, a UW professor in the Paul G. Allen School of Computer Science &amp; Engineering. “Our insight is that when we’re conversing with a specific group of people, our speech naturally follows a turn-taking rhythm. And we can train AI to predict and track those rhythms using only audio, without the need for implanting electrodes.”</span></p>
  <div>
  <p><strong>Related:</strong></p>
  <ul>
  <li>For more information, visit <a>the team’s website</a>
  </li>
  <li>Story from <a>IEEE Spectrum</a>
  </li>
  </ul>
  </div>
  <p><span>The prototype system, dubbed “proactive hearing assistants,” activates when the person wearing the headphones begins speaking. From there, one AI model begins tracking conversation participants by performing a “who spoke when” analysis and looking for low overlap in exchanges. The system then forwards the result to a second model which isolates the participants and plays the cleaned up audio for the wearer. The system is fast enough to avoid confusing audio lag for the user, and can currently juggle one to four conversation partners in addition to the wearer’s audio.</span></p>
  <p><span>The team tested the headphones with 11 participants, who rated qualities like noise suppression and comprehension with and without the AI filtration. Overall, the group rated the filtered audio more than twice as favorably as the baseline. </span></p>
  <div>
  <img src="https://uw-s3-cdn.s3.us-west-2.amazonaws.com/wp-content/uploads/sites/6/2025/11/14101410/proactive_listening_prototype-scaled.jpg">
  <p>The team combined off-the-shelf noise-canceling headphones with binaural microphones to create the prototype, pictured here.<span>Hu et al./EMNLP</span></p>
  </div>
  <p><span>Gollakota’s team has been experimenting with AI-powered hearing assistants for the past few years. They developed one smart headphone prototype that can </span><a><span>pick a person’s audio out of a crowd when the wearer looks at them</span></a><span>, and another that </span><a><span>creates a “sound bubble”</span></a><span> by muting all sounds within a set distance of the wearer. </span></p>
  <p><span>“Everything we’ve done previously requires the user to manually select a specific speaker or a distance within which to listen, which is not great for user experience,” said lead author Guilin Hu, a doctoral student in the</span><span> Allen School</span><span>. “What we’ve demonstrated is a technology that’s proactive — something that infers human intent noninvasively and automatically.”</span></p>
  <p><span>Plenty of work remains to refine the experience. The more dynamic a conversation gets, the more the system is likely to struggle, as participants talk over one another or speak in longer monologues. Participants entering and leaving a conversation present another hurdle, though Gollakota was surprised by how well the current prototype performed in these more complicated scenarios. The authors also note that the models were tested on English, Mandarin and Japanese dialog, and that the rhythms of other languages might require further fine-tuning.</span></p>
  <p><span>The current prototype uses commercial over-the-ear headphones, microphones and circuitry. Eventually, Gollakota expects to make the system small enough to run on a tiny chip within an earbud or a hearing aid. In </span><a><span>concurrent work</span></a><span> that appeared at </span><a><span>MobiCom 2025</span></a><span>, the authors demonstrated that it is possible to run AI models on tiny hearing aid devices.</span></p>
  <p><i><span>Co-authors include </span></i><a><i><span>Malek Itani</span></i></a><i><span> and </span></i><a><i><span>Tuochao Chen</span></i></a><i><span>, UW doctoral students in the Allen School.</span></i></p>
  <p><i><span>This research was funded by the Moore Inventor Fellows program.</span></i></p>
  <p><i><span>For more information, contact <a>proactivehearing@cs.washington.edu </a></span></i></p>
  <p><a></a><a></a><a></a><a></a><a></a><a></a></p>
feed_content_checksum: 14770966ac71d13a7d0e1d7782c0c5a4ad310bc6
image_ids: []
locations: []
published: false
source: University of Washington
source_url: https://www.washington.edu/news/2025/12/09/ai-headphones-smart-noise-cancellation-proactive-listening/
summarized: true
title: AI headphones automatically learn who you’re talking to — and let you hear
  them better
topics: []
---

Researchers at the University of Washington have created smart headphones designed to tackle the “cocktail party problem,” where users struggle to hear conversations in noisy environments. These headphones use artificial intelligence to isolate voices by detecting conversation patterns. The technology relies on two AI models: one analyzes who is speaking and when, while the other filters out unwanted noises. This system, dubbed "proactive hearing assistants," activates when the user speaks and can manage one to four conversation partners without lag.

In tests with 11 participants, users rated the audio quality with AI filtering over twice as favorably compared to standard audio. The prototype combines noise-canceling headphones with binaural microphones and is built on open-source code. The researchers aim to make the technology compact enough for earbuds or hearing aids and have previously developed models that require user input to select speakers. They believe this new approach allows for a more seamless user experience. Challenges remain, particularly in dynamic conversations with overlapping speech, and further refinements are needed for different languages. The research was presented at the Conference on Empirical Methods in Natural Language Processing in Suzhou, China.
