---
layout: default
permalink: "/contact-us/"
title: Contact Us
---

<section class="contact-page">
  <header>
    <h1>Contact King County Solutions</h1>
  </header>
  <p>
    Share questions, feature requests, or feedback about the site. Provide the best email address to reach you and describe the assistance you need so we can respond quickly.
  </p>

  <form class="contact-form" action="{{ site.contact_form.action }}" method="POST" novalidate>
    <label for="contact-email">Your email address</label>
    <input
      id="contact-email"
      name="_replyto"
      type="email"
      autocomplete="email"
      placeholder="you@example.com"
      required
    />

    <label for="contact-request">How can we help?</label>
    <textarea
      id="contact-request"
      name="request"
      placeholder="Tell us what you need (e.g., a missing organization, a question about services, etc.)"
      required
    ></textarea>

    <input type="hidden" name="_subject" value="{{ site.contact_form.subject }}" />
    <input type="hidden" name="_next" value="{{ site.url }}{{ site.contact_form.next | relative_url }}" />
    <input type="hidden" name="_honey" value="" />

    <button type="submit">Send request</button>
  </form>
</section>
