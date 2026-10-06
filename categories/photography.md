---
title: Photography posts
layout: postlist
group: photography
permalink: /categories/photography/
---


<!-- This loops through the photography collection (_photography/), newest first -->
{% assign photo_posts = site.photography | reverse %}
{% for post in photo_posts %}
  <hr>
  <h2><a href="{{ post.url }}">{{ post.title }}</a></h2>
  <p class="author">
    <span class="author">{{post.author}}</span><br>
    <span class="date"><em>{{ post.date | date_to_long_string }}</em></span>
  </p>
  <div class="content">
    {{ post.excerpt }}
  </div>
{% else %}
  <p class="text-muted">No posts (yet)</p>
{% endfor %}
<hr>

