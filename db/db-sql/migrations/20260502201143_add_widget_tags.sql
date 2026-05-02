CREATE TABLE widget_tags (
  widget_id BIGINT NOT NULL REFERENCES widgets (id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  PRIMARY KEY (widget_id, tag)
);
