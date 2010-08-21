--DROP TRIGGER IF EXISTS place_before_insert on placex;
--DROP TRIGGER IF EXISTS place_before_update on placex;
--CREATE TYPE addresscalculationtype AS (
--  word text,
--  score integer
--);


CREATE OR REPLACE FUNCTION isbrokengeometry(place geometry) RETURNS BOOLEAN
  AS $$
DECLARE
  NEWgeometry geometry;
BEGIN
  NEWgeometry := place;
  IF ST_IsEmpty(NEWgeometry) OR NOT ST_IsValid(NEWgeometry) OR ST_X(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') THEN  
    RETURN true;
  END IF;
  RETURN false;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION clean_geometry(place geometry) RETURNS geometry
  AS $$
DECLARE
  NEWgeometry geometry;
BEGIN
  NEWgeometry := place;
  IF ST_X(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') THEN  
    NEWgeometry := ST_buffer(NEWgeometry,0);
    IF ST_X(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') THEN  
      RETURN ST_SetSRID(ST_Point(0,0),4326);
    END IF;
  END IF;
  RETURN NEWgeometry;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION geometry_sector(place geometry) RETURNS INTEGER
  AS $$
DECLARE
  NEWgeometry geometry;
BEGIN
--  RAISE WARNING '%',place;
  NEWgeometry := place;
  IF ST_IsEmpty(NEWgeometry) OR NOT ST_IsValid(NEWgeometry) OR ST_X(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') THEN  
    NEWgeometry := ST_buffer(NEWgeometry,0);
    IF ST_IsEmpty(NEWgeometry) OR NOT ST_IsValid(NEWgeometry) OR ST_X(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') THEN  
      RETURN NULL;
    END IF;
  END IF;
  RETURN (500-ST_X(ST_Centroid(NEWgeometry))::integer)*1000 + (500-ST_Y(ST_Centroid(NEWgeometry))::integer);
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION debug_geometry_sector(osmid integer, place geometry) RETURNS INTEGER
  AS $$
DECLARE
  NEWgeometry geometry;
BEGIN
--  RAISE WARNING '%',osmid;
  IF osmid = 61315 THEN
    return null;
  END IF;
  NEWgeometry := place;
  IF ST_IsEmpty(NEWgeometry) OR NOT ST_IsValid(NEWgeometry) OR ST_X(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') THEN  
    NEWgeometry := ST_buffer(NEWgeometry,0);
    IF ST_IsEmpty(NEWgeometry) OR NOT ST_IsValid(NEWgeometry) OR ST_X(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEWgeometry))::text in ('NaN','Infinity','-Infinity') THEN  
      RETURN NULL;
    END IF;
  END IF;
  RETURN (500-ST_X(ST_Centroid(NEWgeometry))::integer)*1000 + (500-ST_Y(ST_Centroid(NEWgeometry))::integer);
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION geometry_index(place geometry,indexed BOOLEAN,name keyvalue[]) RETURNS INTEGER
  AS $$
BEGIN
IF indexed THEN RETURN NULL; END IF;
IF name is null THEN RETURN NULL; END IF;
RETURN geometry_sector(place);
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION create_tables_location_point() RETURNS BOOLEAN
  AS $$
DECLARE
  i INTEGER;
  postfix TEXT;
BEGIN

  FOR i in 0..26 LOOP

    postfix := '_'||i;

    EXECUTE 'drop table IF EXISTS location_point'||postfix;
    EXECUTE 'CREATE TABLE location_point'||postfix||' ('||
      'place_id bigint,'||
      'country_code varchar(2),'||
      'name keyvalue[],'||
      'keywords TEXT[],'||
      'rank_search INTEGER NOT NULL,'||
      'rank_address INTEGER NOT NULL,'||
      'is_area BOOLEAN NOT NULL'||
      ')';
   EXECUTE 'SELECT AddGeometryColumn(''location_point'||postfix||''', ''centroid'', 4326, ''POINT'', 2)';
   EXECUTE 'CREATE INDEX idx_location_point'||postfix||'_centroid ON location_point'||postfix||' USING GIST (centroid)';
   EXECUTE 'CREATE INDEX idx_location_point'||postfix||'_sector ON location_point'||postfix||' USING BTREE (geometry_sector(centroid))';
   EXECUTE 'CREATE INDEX idx_location_point'||postfix||'_place_id ON location_point'||postfix||' USING BTREE (place_id)';
   EXECUTE 'CLUSTER location_point'||postfix||' USING idx_location_point'||postfix||'_sector';
  END LOOP;

  RETURN true;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transliteration(text) RETURNS text
  AS '/home/twain/osm2pgsql2/gazetteer/gazetteer.so', 'transliteration'
LANGUAGE c IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION gettokenstring(text) RETURNS text
  AS '/home/twain/osm2pgsql2/gazetteer/gazetteer.so', 'gettokenstring'
LANGUAGE c IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION make_standard_name(name TEXT) RETURNS TEXT
  AS $$
DECLARE
  o TEXT;
BEGIN
  o := gettokenstring(transliteration(name));
  RETURN trim(substr(o,1,length(o)));
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE OR REPLACE FUNCTION getorcreate_word_id(lookup_word TEXT) 
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := trim(lookup_word);
  SELECT min(word_id) FROM word WHERE word_token = lookup_token and class is null and type is null into return_word_id;
  IF return_word_id IS NULL THEN
    return_word_id := nextval('seq_word');
    INSERT INTO word VALUES (return_word_id, lookup_token, regexp_replace(lookup_token,E'([^0-9])\\1+',E'\\1','g'), null, null, null, null, 0, null);
  END IF;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getorcreate_housenumber_id(lookup_word TEXT)
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := ' '||trim(lookup_word);
  SELECT min(word_id) FROM word WHERE word_token = lookup_token and class='place' and type='house' into return_word_id;
  IF return_word_id IS NULL THEN
    return_word_id := nextval('seq_word');
    INSERT INTO word VALUES (return_word_id, lookup_token, null, null, 'place', 'house', null, 0, null);
  END IF;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getorcreate_country(lookup_word TEXT, lookup_country_code varchar(2))
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := ' '||trim(lookup_word);
  SELECT min(word_id) FROM word WHERE word_token = lookup_token and country_code=lookup_country_code into return_word_id;
  IF return_word_id IS NULL THEN
    return_word_id := nextval('seq_word');
    INSERT INTO word VALUES (return_word_id, lookup_token, null, null, null, null, lookup_country_code, 0, null);
  END IF;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getorcreate_amenity(lookup_word TEXT, lookup_class text, lookup_type text)
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := ' '||trim(lookup_word);
  SELECT min(word_id) FROM word WHERE word_token = lookup_token and class=lookup_class and type = lookup_type into return_word_id;
  IF return_word_id IS NULL THEN
    return_word_id := nextval('seq_word');
    INSERT INTO word VALUES (return_word_id, lookup_token, null, null, lookup_class, lookup_type, null, 0, null);
  END IF;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getorcreate_tagpair(lookup_class text, lookup_type text)
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := lookup_class||'='||lookup_type;
  SELECT min(word_id) FROM word WHERE word_token = lookup_token into return_word_id;
  IF return_word_id IS NULL THEN
    return_word_id := nextval('seq_word');
    INSERT INTO word VALUES (return_word_id, lookup_token, null, null, null, null, null, 0, null);
  END IF;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_tagpair(lookup_class text, lookup_type text)
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := lookup_class||'='||lookup_type;
  SELECT min(word_id) FROM word WHERE word_token = lookup_token into return_word_id;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getorcreate_amenityoperator(lookup_word TEXT, lookup_class text, lookup_type text, op text)
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := ' '||trim(lookup_word);
  SELECT min(word_id) FROM word WHERE word_token = lookup_token and class=lookup_class and type = lookup_type and operator = op into return_word_id;
  IF return_word_id IS NULL THEN
    return_word_id := nextval('seq_word');
    INSERT INTO word VALUES (return_word_id, lookup_token, null, null, lookup_class, lookup_type, null, 0, null, op);
  END IF;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getorcreate_name_id(lookup_word TEXT, src_word TEXT) 
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  nospace_lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := ' '||trim(lookup_word);
  SELECT min(word_id) FROM word WHERE word_token = lookup_token and class is null and type is null into return_word_id;
  IF return_word_id IS NULL THEN
    return_word_id := nextval('seq_word');
    INSERT INTO word VALUES (return_word_id, lookup_token, regexp_replace(lookup_token,E'([^0-9])\\1+',E'\\1','g'), src_word, null, null, null, 0, null);
    nospace_lookup_token := replace(replace(lookup_token, '-',''), ' ','');
    IF ' '||nospace_lookup_token != lookup_token THEN
      INSERT INTO word VALUES (return_word_id, '-'||nospace_lookup_token, null, src_word, null, null, null, 0, null);
    END IF;
  END IF;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getorcreate_name_id(lookup_word TEXT) 
  RETURNS INTEGER
  AS $$
DECLARE
BEGIN
  RETURN getorcreate_name_id(lookup_word, '');
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_word_id(lookup_word TEXT) 
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := trim(lookup_word);
  SELECT min(word_id) FROM word WHERE word_token = lookup_token and class is null and type is null into return_word_id;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION get_name_id(lookup_word TEXT) 
  RETURNS INTEGER
  AS $$
DECLARE
  lookup_token TEXT;
  return_word_id INTEGER;
BEGIN
  lookup_token := ' '||trim(lookup_word);
  SELECT min(word_id) FROM word WHERE word_token = lookup_token and class is null and type is null into return_word_id;
  RETURN return_word_id;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION array_merge(a INTEGER[], b INTEGER[])
  RETURNS INTEGER[]
  AS $$
DECLARE
  i INTEGER;
  r INTEGER[];
BEGIN
  IF array_upper(a, 1) IS NULL THEN
    RETURN b;
  END IF;
  IF array_upper(b, 1) IS NULL THEN
    RETURN a;
  END IF;
  r := a;
  FOR i IN 1..array_upper(b, 1) LOOP  
    IF NOT (ARRAY[b[i]] && r) THEN
      r := r || b[i];
    END IF;
  END LOOP;
  RETURN r;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION add_keywords(a keyvalue[], b keyvalue[]) RETURNS keyvalue[]
  AS $$
DECLARE
  i INTEGER;
  j INTEGER;
  f BOOLEAN;
  r keyvalue[];
BEGIN
  IF array_upper(a, 1) IS NULL THEN
    RETURN b;
  END IF;
  IF array_upper(b, 1) IS NULL THEN
    RETURN a;
  END IF;
  r := a;
  FOR i IN 1..array_upper(b, 1) LOOP  
    f := false;
    FOR j IN 1..array_upper(a, 1) LOOP  
      IF (a[j].key = b[i].key) THEN
        f := true;
      END IF; 
    END LOOP;
    IF NOT f THEN
      r := r || b[i];
    END IF;
  END LOOP;
  RETURN r;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION make_keywords(src keyvalue[]) RETURNS INTEGER[]
  AS $$
DECLARE
  result INTEGER[];
  s TEXT;
  w INTEGER;
  words TEXT[];
  i INTEGER;
  j INTEGER;
BEGIN
  result := '{}'::INTEGER[];

  IF NOT array_upper(src, 1) IS NULL THEN

    FOR i IN 1..array_upper(src, 1) LOOP

      s := make_standard_name(src[i].value);

      w := getorcreate_name_id(s, src[i].value);
      IF NOT (ARRAY[w] && result) THEN
        result := result || w;
      END IF;

      words := string_to_array(s, ' ');
      IF array_upper(words, 1) IS NOT NULL THEN
        FOR j IN 1..array_upper(words, 1) LOOP
          IF (words[j] != '') THEN
            w = getorcreate_word_id(words[j]);
            IF NOT (ARRAY[w] && result) THEN
              result := result || w;
            END IF;
          END IF;
        END LOOP;
      END IF;

      words := regexp_split_to_array(src[i].value, E'[,;()]');
      IF array_upper(words, 1) != 1 THEN
        FOR j IN 1..array_upper(words, 1) LOOP
          s := make_standard_name(words[j]);
          IF s != '' THEN
            w := getorcreate_word_id(s);
            IF NOT (ARRAY[w] && result) THEN
              result := result || w;
            END IF;
          END IF;
        END LOOP;
      END IF;

      s := regexp_replace(src[i].value, '市$', '');
      IF s != src[i].value THEN
        s := make_standard_name(s);
        IF s != '' THEN
          w := getorcreate_name_id(s, src[i].value);
          IF NOT (ARRAY[w] && result) THEN
            result := result || w;
          END IF;
        END IF;
      END IF;

    END LOOP;
  END IF;
  RETURN result;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION make_keywords(src TEXT) RETURNS INTEGER[]
  AS $$
DECLARE
  result INTEGER[];
  s TEXT;
  w INTEGER;
  words TEXT[];
  i INTEGER;
  j INTEGER;
BEGIN
  result := '{}'::INTEGER[];

  s := make_standard_name(src);
  w := getorcreate_name_id(s);

  IF NOT (ARRAY[w] && result) THEN
    result := result || w;
  END IF;

  words := string_to_array(s, ' ');
  IF array_upper(words, 1) IS NOT NULL THEN
    FOR j IN 1..array_upper(words, 1) LOOP
      IF (words[j] != '') THEN
        w = getorcreate_word_id(words[j]);
        IF NOT (ARRAY[w] && result) THEN
          result := result || w;
        END IF;
      END IF;
    END LOOP;
  END IF;

  RETURN result;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION get_word_score(wordscores wordscore[], words text[]) RETURNS integer
  AS $$
DECLARE
  idxword integer;
  idxscores integer;
  result integer;
BEGIN
  IF (wordscores is null OR words is null) THEN
    RETURN 0;
  END IF;

  result := 0;
  FOR idxword in 1 .. array_upper(words, 1) LOOP
    FOR idxscores in 1 .. array_upper(wordscores, 1) LOOP
      IF wordscores[idxscores].word = words[idxword] THEN
        result := result + wordscores[idxscores].score;
      END IF;
    END LOOP;
  END LOOP;

  RETURN result;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION get_country_code(place geometry) RETURNS TEXT
  AS $$
DECLARE
  nearcountry RECORD;
BEGIN
  FOR nearcountry IN select country_code from location_area where ST_Contains(area, ST_Centroid(place)) and country_code is not null order by rank_address asc limit 1
  LOOP
    RETURN lower(nearcountry.country_code);
  END LOOP;
  -- Are we in a country? Ignore the error condition of being in multiple countries
  FOR nearcountry IN select distinct country_code from country where ST_Contains(country.geometry, ST_Centroid(place)) limit 1
  LOOP
    RETURN lower(nearcountry.country_code);
  END LOOP;
  -- Not in a country - try nearest withing 12 miles of a country
  FOR nearcountry IN select country_code from country where st_distance(country.geometry, ST_Centroid(place)) < 0.5 order by st_distance(country.geometry, place) asc limit 1
  LOOP
    RETURN lower(nearcountry.country_code);
  END LOOP;
  RETURN NULL;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION get_country_language_code(search_country_code VARCHAR(2)) RETURNS TEXT
  AS $$
DECLARE
  nearcountry RECORD;
BEGIN
  FOR nearcountry IN select distinct country_default_language_code from country where country_code = search_country_code limit 1
  LOOP
    RETURN lower(nearcountry.country_default_language_code);
  END LOOP;
  RETURN NULL;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION delete_location(OLD_place_id BIGINT) RETURNS BOOLEAN
  AS $$
DECLARE
BEGIN
  DELETE FROM location_area where place_id = OLD_place_id;
  DELETE FROM location_point where place_id = OLD_place_id;
  DELETE FROM location_point_0 where place_id = OLD_place_id;
  DELETE FROM location_point_1 where place_id = OLD_place_id;
  DELETE FROM location_point_2 where place_id = OLD_place_id;
  DELETE FROM location_point_3 where place_id = OLD_place_id;
  DELETE FROM location_point_4 where place_id = OLD_place_id;
  DELETE FROM location_point_5 where place_id = OLD_place_id;
  DELETE FROM location_point_6 where place_id = OLD_place_id;
  DELETE FROM location_point_7 where place_id = OLD_place_id;
  DELETE FROM location_point_8 where place_id = OLD_place_id;
  DELETE FROM location_point_9 where place_id = OLD_place_id;
  DELETE FROM location_point_10 where place_id = OLD_place_id;
  DELETE FROM location_point_11 where place_id = OLD_place_id;
  DELETE FROM location_point_12 where place_id = OLD_place_id;
  DELETE FROM location_point_13 where place_id = OLD_place_id;
  DELETE FROM location_point_14 where place_id = OLD_place_id;
  DELETE FROM location_point_15 where place_id = OLD_place_id;
  DELETE FROM location_point_16 where place_id = OLD_place_id;
  DELETE FROM location_point_17 where place_id = OLD_place_id;
  DELETE FROM location_point_18 where place_id = OLD_place_id;
  DELETE FROM location_point_19 where place_id = OLD_place_id;
  DELETE FROM location_point_20 where place_id = OLD_place_id;
  DELETE FROM location_point_21 where place_id = OLD_place_id;
  DELETE FROM location_point_22 where place_id = OLD_place_id;
  DELETE FROM location_point_23 where place_id = OLD_place_id;
  DELETE FROM location_point_24 where place_id = OLD_place_id;
  DELETE FROM location_point_25 where place_id = OLD_place_id;
  DELETE FROM location_point_26 where place_id = OLD_place_id;
  RETURN true;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_location(
    place_id BIGINT,
    place_country_code varchar(2),
    name keyvalue[],
    rank_search INTEGER,
    rank_address INTEGER,
    geometry GEOMETRY
  ) 
  RETURNS BOOLEAN
  AS $$
DECLARE
  keywords INTEGER[];
  country_code VARCHAR(2);
  locationid INTEGER;
  isarea BOOLEAN;
BEGIN

  -- Allocate all tokens ids - prevents multi-processor race condition later on
  keywords := make_keywords(name);

  -- 26 = street/highway
  IF rank_search < 26 THEN
    IF place_country_code IS NULL THEN
      country_code := get_country_code(geometry);
    END IF;
    country_code := lower(place_country_code);

    isarea := false;
    IF (ST_GeometryType(geometry) in ('ST_Polygon','ST_MultiPolygon') AND ST_IsValid(geometry)) THEN
      INSERT INTO location_area values (place_id,country_code,name,keywords,
        rank_search,rank_address,ST_Centroid(geometry),geometry);
      isarea := true;
    END IF;

    INSERT INTO location_point values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF not isarea THEN
    IF rank_search < 26 THEN
      INSERT INTO location_point_26 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 25 THEN
      INSERT INTO location_point_25 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 24 THEN
      INSERT INTO location_point_24 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 23 THEN
      INSERT INTO location_point_23 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 22 THEN
      INSERT INTO location_point_22 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 21 THEN
      INSERT INTO location_point_21 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 20 THEN
      INSERT INTO location_point_20 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 19 THEN
      INSERT INTO location_point_19 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 18 THEN
      INSERT INTO location_point_18 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 17 THEN
      INSERT INTO location_point_17 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 16 THEN
      INSERT INTO location_point_16 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 15 THEN
      INSERT INTO location_point_15 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 14 THEN
      INSERT INTO location_point_14 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 13 THEN
      INSERT INTO location_point_13 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 12 THEN
      INSERT INTO location_point_12 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 11 THEN
      INSERT INTO location_point_11 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 10 THEN
      INSERT INTO location_point_10 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 9 THEN
      INSERT INTO location_point_9 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 8 THEN
      INSERT INTO location_point_8 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 7 THEN
      INSERT INTO location_point_7 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 6 THEN
      INSERT INTO location_point_6 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 5 THEN
      INSERT INTO location_point_5 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 4 THEN
      INSERT INTO location_point_4 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 3 THEN
      INSERT INTO location_point_3 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 2 THEN
      INSERT INTO location_point_2 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    IF rank_search < 1 THEN
      INSERT INTO location_point_1 values (place_id,country_code,name,keywords,rank_search,rank_address,isarea,ST_Centroid(geometry));
    END IF;END IF;END IF;END IF;END IF;END IF;END IF;END IF;END IF;END IF;
    END IF;END IF;END IF;END IF;END IF;END IF;END IF;END IF;END IF;END IF;
    END IF;END IF;END IF;END IF;END IF;END IF;END IF;
    RETURN true;
  END IF;
  RETURN false;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_location(
    place_id BIGINT,
    place_country_code varchar(2),
    name keyvalue[],
    rank_search INTEGER,
    rank_address INTEGER,
    geometry GEOMETRY
  ) 
  RETURNS BOOLEAN
  AS $$
DECLARE
  b BOOLEAN;
BEGIN
  b := delete_location(place_id);
  RETURN add_location(place_id, place_country_code, name, rank_search, rank_address, geometry);
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION search_name_add_words(parent_place_id BIGINT, to_add INTEGER[])
  RETURNS BOOLEAN
  AS $$
DECLARE
  childplace RECORD;
BEGIN

  IF #to_add = 0 THEN
    RETURN true;
  END IF;

  -- this should just be an update, but it seems to do insane things to the index size (delete and insert doesn't)
  FOR childplace IN select * from search_name,place_addressline 
    where  address_place_id = parent_place_id
      and search_name.place_id = place_addressline.place_id
  LOOP
    delete from search_name where place_id = childplace.place_id;
    childplace.nameaddress_vector := uniq(sort_asc(childplace.nameaddress_vector + to_add));
    IF childplace.place_id = parent_place_id THEN
      childplace.name_vector := uniq(sort_asc(childplace.name_vector + to_add));
    END IF;
    insert into search_name (place_id, search_rank, address_rank, country_code, name_vector, nameaddress_vector, centroid) 
      values (childplace.place_id, childplace.search_rank, childplace.address_rank, childplace.country_code, 
        childplace.name_vector, childplace.nameaddress_vector, childplace.centroid);
  END LOOP;

  RETURN true;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_location_nameonly(OLD_place_id BIGINT, name keyvalue[]) RETURNS BOOLEAN
  AS $$
DECLARE
  newkeywords INTEGER[];
  addedkeywords INTEGER[];
  removedkeywords INTEGER[];
BEGIN

  -- what has changed?
  newkeywords := make_keywords(name);
  select coalesce(newkeywords,'{}'::INTEGER[]) - coalesce(location_point.keywords,'{}'::INTEGER[]), 
    coalesce(location_point.keywords,'{}'::INTEGER[]) - coalesce(newkeywords,'{}'::INTEGER[]) from location_point 
    where place_id = OLD_place_id into addedkeywords, removedkeywords;

  RAISE WARNING 'update_location_nameonly for %: new:% added:% removed:%', OLD_place_id, newkeywords, addedkeywords, removedkeywords;

  IF #removedkeywords > 0 THEN
    -- abort due to tokens removed
    RETURN false;
  END IF;
  
  IF #addedkeywords > 0 THEN
    -- short circuit - no changes
    RETURN true;
  END IF;

  UPDATE location_area set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_0 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_1 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_2 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_3 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_4 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_5 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_6 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_7 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_8 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_9 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_10 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_11 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_12 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_13 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_14 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_15 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_16 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_17 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_18 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_19 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_20 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_21 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_22 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_23 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_24 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_25 set keywords = newkeywords where place_id = OLD_place_id;
  UPDATE location_point_26 set keywords = newkeywords where place_id = OLD_place_id;

  RETURN search_name_add_words(OLD_place_id, addedkeywords);
END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION create_interpolation(wayid BIGINT, interpolationtype TEXT) RETURNS INTEGER
  AS $$
DECLARE
  
  newpoints INTEGER;
  waynodes integer[];
  nodeid INTEGER;
  prevnode RECORD;
  nextnode RECORD;
  startnumber INTEGER;
  endnumber INTEGER;
  stepsize INTEGER;
  orginalstartnumber INTEGER;
  originalnumberrange INTEGER;
  housenum INTEGER;
  linegeo GEOMETRY;
  search_place_id INTEGER;

  havefirstpoint BOOLEAN;
  linestr TEXT;
BEGIN
  newpoints := 0;
  IF interpolationtype = 'odd' OR interpolationtype = 'even' OR interpolationtype = 'all' THEN

    select nodes from planet_osm_ways where id = wayid INTO waynodes;
--RAISE WARNING 'interpolation % % %',wayid,interpolationtype,waynodes;
    IF array_upper(waynodes, 1) IS NOT NULL THEN

      havefirstpoint := false;

      FOR nodeidpos in 1..array_upper(waynodes, 1) LOOP

        select min(place_id) from placex where osm_type = 'N' and osm_id = waynodes[nodeidpos]::bigint and type = 'house' INTO search_place_id;
        IF search_place_id IS NULL THEN
          -- null record of right type
          select * from placex where osm_type = 'N' and osm_id = waynodes[nodeidpos]::bigint and type = 'house' limit 1 INTO nextnode;
          select ST_SetSRID(ST_Point(lon::float/10000000,lat::float/10000000),4326) from planet_osm_nodes where id = waynodes[nodeidpos] INTO nextnode.geometry;
        ELSE
          select * from placex where place_id = search_place_id INTO nextnode;
        END IF;

--RAISE WARNING 'interpolation node % % % ',nextnode.housenumber,ST_X(nextnode.geometry),ST_Y(nextnode.geometry);
      
        IF havefirstpoint THEN

          -- add point to the line string
          linestr := linestr||','||ST_X(nextnode.geometry)||' '||ST_Y(nextnode.geometry);
          endnumber := ('0'||substring(nextnode.housenumber,'[0-9]+'))::integer;

          IF startnumber IS NOT NULL and startnumber > 0 AND endnumber IS NOT NULL and endnumber > 0 THEN

--RAISE WARNING 'interpolation end % % ',nextnode.place_id,endnumber;

            IF startnumber != endnumber THEN

              linestr := linestr || ')';
--RAISE WARNING 'linestr %',linestr;
              linegeo := ST_GeomFromText(linestr,4326);
              linestr := 'LINESTRING('||ST_X(nextnode.geometry)||' '||ST_Y(nextnode.geometry);
              IF (startnumber > endnumber) THEN
                housenum := endnumber;
                endnumber := startnumber;
                startnumber := housenum;
                linegeo := ST_Reverse(linegeo);
              END IF;
              orginalstartnumber := startnumber;
              originalnumberrange := endnumber - startnumber;

-- Too much broken data worldwide for this test to be worth using
--              IF originalnumberrange > 500 THEN
--                RAISE WARNING 'Number block of % while processing % %', originalnumberrange, prevnode, nextnode;
--              END IF;

              IF (interpolationtype = 'odd' AND startnumber%2 = 0) OR (interpolationtype = 'even' AND startnumber%2 = 1) THEN
                startnumber := startnumber + 1;
                stepsize := 2;
              ELSE
                IF (interpolationtype = 'odd' OR interpolationtype = 'even') THEN
                  startnumber := startnumber + 2;
                  stepsize := 2;
                ELSE -- everything else assumed to be 'all'
                  startnumber := startnumber + 1;
                  stepsize := 1;
                END IF;
              END IF;
              endnumber := endnumber - 1;
              delete from placex where osm_type = 'N' and osm_id = prevnode.osm_id and type = 'house' and place_id != prevnode.place_id;
              FOR housenum IN startnumber..endnumber BY stepsize LOOP
                -- this should really copy postcodes but it puts a huge burdon on the system for no big benefit
                -- ideally postcodes should move up to the way
                insert into placex values (null,'N',prevnode.osm_id,prevnode.class,prevnode.type,NULL,prevnode.admin_level,housenum,prevnode.street,prevnode.isin,null,prevnode.country_code,prevnode.street_place_id,prevnode.rank_address,prevnode.rank_search,false,ST_Line_Interpolate_Point(linegeo, (housenum::float-orginalstartnumber::float)/originalnumberrange::float));
                newpoints := newpoints + 1;
--RAISE WARNING 'interpolation number % % ',prevnode.place_id,housenum;
              END LOOP;
            END IF;
            havefirstpoint := false;
          END IF;
        END IF;

        IF NOT havefirstpoint THEN
          startnumber := ('0'||substring(nextnode.housenumber,'[0-9]+'))::integer;
          IF startnumber IS NOT NULL AND startnumber > 0 THEN
            havefirstpoint := true;
            linestr := 'LINESTRING('||ST_X(nextnode.geometry)||' '||ST_Y(nextnode.geometry);
            prevnode := nextnode;
          END IF;
--RAISE WARNING 'interpolation start % % ',nextnode.place_id,startnumber;
        END IF;
      END LOOP;
    END IF;
  END IF;

--RAISE WARNING 'interpolation points % ',newpoints;

  RETURN newpoints;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION placex_insert() RETURNS TRIGGER
  AS $$
DECLARE
  i INTEGER;
  postcode TEXT;
  result BOOLEAN;
  country_code VARCHAR(2);
  diameter FLOAT;
BEGIN
--  RAISE WARNING '%',NEW.osm_id;
--  RAISE WARNING '%',NEW.osm_id;

  -- just block these
  IF NEW.class = 'highway' and NEW.type in ('turning_circle','traffic_signals','mini_roundabout','noexit','crossing') THEN
    RETURN null;
  END IF;
  IF NEW.class in ('landuse','natural') and NEW.name is null THEN
    RETURN null;
  END IF;

--  RAISE WARNING '%',NEW.osm_id;

  IF ST_IsEmpty(NEW.geometry) OR NOT ST_IsValid(NEW.geometry) OR ST_X(ST_Centroid(NEW.geometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEW.geometry))::text in ('NaN','Infinity','-Infinity') THEN  
    -- block all invalid geometary - just not worth the risk.  seg faults are causing serious problems.
    RETURN NULL;
    IF NEW.osm_type = 'R' THEN
      -- invalid multipolygons can crash postgis, don't even bother to try!
      RETURN NULL;
    END IF;
    NEW.geometry := ST_buffer(NEW.geometry,0);
    IF ST_IsEmpty(NEW.geometry) OR NOT ST_IsValid(NEW.geometry) OR ST_X(ST_Centroid(NEW.geometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEW.geometry))::text in ('NaN','Infinity','-Infinity') THEN  
      RAISE WARNING 'Invalid geometary, rejecting: % %', NEW.osm_type, NEW.osm_id;
      RETURN NULL;
    END IF;
  END IF;

  NEW.place_id := nextval('seq_place');
  NEW.indexed := false;
  NEW.country_code := lower(NEW.country_code);

--RAISE WARNING '%',NEW.country_code;

  IF NEW.housenumber IS NOT NULL THEN
    i := getorcreate_housenumber_id(make_standard_name(NEW.housenumber));
  END IF;

  IF NEW.osm_type = 'X' THEN
    -- E'X'ternal records should already be in the right format so do nothing
  ELSE
    NEW.rank_search := 30;
    NEW.rank_address := NEW.rank_search;

    -- By doing in postgres we have the country available to us - currently only used for postcode
    IF NEW.class = 'place' THEN
      IF NEW.type in ('continent') THEN
        NEW.rank_search := 2;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('sea') THEN
        NEW.rank_search := 2;
        NEW.rank_address := 0;
      ELSEIF NEW.type in ('country') THEN
        NEW.rank_search := 4;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('state') THEN
        NEW.rank_search := 8;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('region') THEN
        NEW.rank_search := 10;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('county') THEN
        NEW.rank_search := 12;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('city') THEN
        NEW.rank_search := 16;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('island') THEN
        NEW.rank_search := 17;
        NEW.rank_address := 0;
      ELSEIF NEW.type in ('town') THEN
        NEW.rank_search := 17;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('village','hamlet','municipality','district','unincorporated_area','borough') THEN
        NEW.rank_search := 18;
        NEW.rank_address := 17;
      ELSEIF NEW.type in ('airport') AND ST_GeometryType(NEW.geometry) in ('ST_Polygon','ST_MultiPolygon') THEN
        NEW.rank_search := 18;
        NEW.rank_address := 17;
      ELSEIF NEW.type in ('moor') AND ST_GeometryType(NEW.geometry) in ('ST_Polygon','ST_MultiPolygon') THEN
        NEW.rank_search := 17;
        NEW.rank_address := 18;
      ELSEIF NEW.type in ('moor') THEN
        NEW.rank_search := 17;
        NEW.rank_address := 0;
      ELSEIF NEW.type in ('national_park') THEN
        NEW.rank_search := 18;
        NEW.rank_address := 18;
      ELSEIF NEW.type in ('suburb','croft','subdivision') THEN
        NEW.rank_search := 20;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('farm','locality','islet') THEN
        NEW.rank_search := 20;
        NEW.rank_address := 0;
      ELSEIF NEW.type in ('hall_of_residence','neighbourhood','housing_estate','nature_reserve') THEN
        NEW.rank_search := 22;
        NEW.rank_address := 22;
      ELSEIF NEW.type in ('postcode') THEN

        -- Postcode processing is very country dependant
        IF NEW.country_code IS NULL THEN
          NEW.country_code := get_country_code(NEW.geometry);
        END IF;

        IF NEW.country_code = 'gb' THEN
          IF NEW.postcode ~ '^([A-Z][A-Z]?[0-9][0-9A-Z]? [0-9][A-Z][A-Z])$' THEN
            NEW.rank_search := 25;
            NEW.rank_address := 5;
            NEW.name := ARRAY[ROW('ref',NEW.postcode)::keyvalue];
          ELSEIF NEW.postcode ~ '^([A-Z][A-Z]?[0-9][0-9A-Z]? [0-9])$' THEN
            NEW.rank_search := 23;
            NEW.rank_address := 5;
            NEW.name := ARRAY[ROW('ref',NEW.postcode)::keyvalue];
          ELSEIF NEW.postcode ~ '^([A-Z][A-Z]?[0-9][0-9A-Z])$' THEN
            NEW.rank_search := 21;
            NEW.rank_address := 5;
            NEW.name := ARRAY[ROW('ref',NEW.postcode)::keyvalue];
          END IF;

        ELSEIF NEW.country_code = 'de' THEN
          IF NEW.postcode ~ '^([0-9]{5})$' THEN
            NEW.name := ARRAY[ROW('ref',NEW.postcode)::keyvalue];
            NEW.rank_search := 21;
            NEW.rank_address := 11;
          END IF;

        ELSE
          -- Guess at the postcode format and coverage (!)
          IF upper(NEW.postcode) ~ '^[A-Z0-9]{1,5}$' THEN -- Probably too short to be very local
            NEW.name := ARRAY[ROW('ref',NEW.postcode)::keyvalue];
            NEW.rank_search := 21;
            NEW.rank_address := 11;
          ELSE
            -- Does it look splitable into and area and local code?
            postcode := substring(upper(NEW.postcode) from '^([- :A-Z0-9]+)([- :][A-Z0-9]+)$');

            IF postcode IS NOT NULL THEN

              -- TODO: insert new line into location instead
              --result := add_location(NEW.place_id,NEW.country_code,ARRAY[ROW('ref',postcode)::keyvalue],21,11,NEW.geometry);

              NEW.name := ARRAY[ROW('ref',NEW.postcode)::keyvalue];
              NEW.rank_search := 25;
              NEW.rank_address := 11;
            ELSEIF NEW.postcode ~ '^[- :A-Z0-9]{6,}$' THEN
              NEW.name := ARRAY[ROW('ref',NEW.postcode)::keyvalue];
              NEW.rank_search := 21;
              NEW.rank_address := 11;
            END IF;
          END IF;
        END IF;

      ELSEIF NEW.type in ('airport','street') THEN
        NEW.rank_search := 26;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('house','building') THEN
        NEW.rank_search := 28;
        NEW.rank_address := NEW.rank_search;
      ELSEIF NEW.type in ('houses') THEN
        -- can't guarantee all required nodes loaded yet due to caching in osm2pgsql
        -- insert new point into place for each derived building
        --i := create_interpolation(NEW.osm_id, NEW.housenumber);
      END IF;

    ELSEIF NEW.class = 'boundary' THEN
      IF NEW.country_code is null THEN
        NEW.country_code := get_country_code(NEW.geometry);
      END IF;
      NEW.rank_search := NEW.admin_level * 2;
      NEW.rank_address := NEW.rank_search;
    ELSEIF NEW.class = 'landuse' AND ST_GeometryType(NEW.geometry) in ('ST_Polygon','ST_MultiPolygon') THEN
      NEW.rank_search := 22;
      NEW.rank_address := NEW.rank_search;
    -- any feature more than 5 square miles is probably worth indexing
    ELSEIF ST_GeometryType(NEW.geometry) in ('ST_Polygon','ST_MultiPolygon') AND ST_Area(NEW.geometry) > 0.1 THEN
      NEW.rank_search := 22;
      NEW.rank_address := NEW.rank_search;
    ELSEIF NEW.class = 'highway' AND NEW.name is NULL AND 
           NEW.type in ('service','cycleway','path','footway','steps','bridleway','track','byway','motorway_link','primary_link','trunk_link','secondary_link','tertiary_link') THEN
      RETURN NULL;
    ELSEIF NEW.class = 'railway' AND NEW.type in ('rail') THEN
      RETURN NULL;
    ELSEIF NEW.class = 'waterway' AND NEW.name is NULL THEN
      RETURN NULL;
    ELSEIF NEW.class = 'waterway' THEN
      NEW.rank_address := 17;
    ELSEIF NEW.class = 'highway' AND NEW.osm_type != 'N' AND NEW.type in ('service','cycleway','path','footway','steps','bridleway','motorway_link','primary_link','trunk_link','secondary_link','tertiary_link') THEN
      NEW.rank_search := 27;
      NEW.rank_address := NEW.rank_search;
    ELSEIF NEW.class = 'highway' AND NEW.osm_type != 'N' THEN
      NEW.rank_search := 26;
      NEW.rank_address := NEW.rank_search;
    ELSEIF NEW.class = 'natural' and NEW.type = 'sea' THEN
      NEW.rank_search := 4;
      NEW.rank_address := NEW.rank_search;
    ELSEIF NEW.class = 'natural' and NEW.type in ('peak','volcano') THEN
      NEW.rank_search := 18;
      NEW.rank_address := 0;
    END IF;

  END IF;

  IF array_upper(NEW.name, 1) is not null THEN
    result := add_location(NEW.place_id,NEW.country_code,NEW.name,NEW.rank_search,NEW.rank_address,NEW.geometry);
  END IF;

  --RETURN NEW;
  -- The following is not needed until doing diff updates, and slows the main index process down

  IF (ST_GeometryType(NEW.geometry) in ('ST_Polygon','ST_MultiPolygon') AND ST_IsValid(NEW.geometry)) THEN
    -- Performance: We just can't handle re-indexing for country level changes
    IF st_area(NEW.geometry) < 1 THEN
      -- mark items within the geometry for re-indexing
--    RAISE WARNING 'placex poly insert: % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type;
-- work around bug in postgis
      update placex set indexed = false where indexed and (ST_Contains(NEW.geometry, placex.geometry) OR ST_Intersects(NEW.geometry, placex.geometry)) 
       AND rank_search > NEW.rank_search and ST_geometrytype(placex.geometry) = 'ST_Point';
      update placex set indexed = false where indexed and (ST_Contains(NEW.geometry, placex.geometry) OR ST_Intersects(NEW.geometry, placex.geometry)) 
       AND rank_search > NEW.rank_search and ST_geometrytype(placex.geometry) != 'ST_Point';
    END IF;
  ELSE
    -- mark nearby items for re-indexing, where 'nearby' depends on the features rank_search and is a complete guess :(
    diameter := 0;
    -- 16 = city, anything higher than city is effectively ignored (polygon required!)
    IF NEW.type='postcode' THEN
      diameter := 0.001;
    ELSEIF NEW.rank_search < 16 THEN
      diameter := 0;
    ELSEIF NEW.rank_search < 18 THEN
      diameter := 0.1;
    ELSEIF NEW.rank_search < 20 THEN
      diameter := 0.05;
    ELSEIF NEW.rank_search = 21 THEN
      diameter := 0.001;
    ELSEIF NEW.rank_search < 24 THEN
      diameter := 0.02;
    ELSEIF NEW.rank_search < 26 THEN
      diameter := 0.002; -- 100 to 200 meters
    ELSEIF NEW.rank_search < 28 THEN
      diameter := 0.001; -- 50 to 100 meters
    END IF;
    IF diameter > 0 THEN
--      RAISE WARNING 'placex point insert: % % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type,diameter;
      update placex set indexed = false where indexed and rank_search > NEW.rank_search and ST_DWithin(placex.geometry, NEW.geometry, diameter);
    END IF;

  END IF;

  IF NEW.rank_search < 26 THEN
    RAISE WARNING 'placex insert: % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type;
  END IF;

  RETURN NEW;

END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION placex_update() RETURNS 
TRIGGER
  AS $$
DECLARE

  place_centroid GEOMETRY;
  place_geometry_text TEXT;

  search_maxdistance FLOAT[];
  search_mindistance FLOAT[];
  address_havelevel BOOLEAN[];
--  search_scores wordscore[];
--  search_scores_pos INTEGER;
  search_country_code_conflict BOOLEAN;

  i INTEGER;
  iMax FLOAT;
  location RECORD;
  relation RECORD;
  search_diameter FLOAT;
  search_prevdiameter FLOAT;
  search_maxrank INTEGER;
  address_maxrank INTEGER;
  address_street_word_id INTEGER;
  street_place_id_count INTEGER;
  isin TEXT[];
  tagpairid INTEGER;

  bPointCountryCode BOOLEAN;

  name_vector INTEGER[];
  nameaddress_vector INTEGER[];

  result BOOLEAN;

BEGIN

--  RAISE WARNING '%',NEW.place_id;
--RAISE WARNING '%', NEW;

  IF NEW.class = 'place' AND NEW.type = 'postcodearea' THEN
    -- Silently do nothing
    RETURN NEW;
  END IF;

  NEW.country_code := lower(NEW.country_code);

  IF NEW.indexed and NOT OLD.indexed THEN

    IF NEW.class = 'place' AND NEW.type = 'houses' THEN
      i := create_interpolation(NEW.osm_id, NEW.housenumber);
      RETURN NEW;
    END IF;

--RAISE WARNING 'PROCESSING: % %', NEW.place_id, NEW.name;

    search_country_code_conflict := false;

    DELETE FROM search_name WHERE place_id = NEW.place_id;
--RAISE WARNING 'x1';
    DELETE FROM place_addressline WHERE place_id = NEW.place_id;
--RAISE WARNING 'x2';
    DELETE FROM place_boundingbox where place_id = NEW.place_id;

    -- Adding ourselves to the list simplifies address calculations later
    INSERT INTO place_addressline VALUES (NEW.place_id, NEW.place_id, true, true, 0, NEW.rank_address); 
--RAISE WARNING 'x3';

    -- What level are we searching from
    search_maxrank := NEW.rank_search;

    -- Default max/min distances to look for a location
    FOR i IN 1..28 LOOP
      search_maxdistance[i] := 1;
      search_mindistance[i] := 0.0;
      address_havelevel[i] := false;
    END LOOP;
    -- Minimum size to search, can be larger but don't let it shink below this
    search_mindistance[14] := 0.2;
    search_mindistance[15] := 0.1;
    search_mindistance[16] := 0.05;
    search_mindistance[17] := 0.03;
    search_mindistance[18] := 0.015;
    search_mindistance[19] := 0.008;
    search_mindistance[20] := 0.006;
    search_mindistance[21] := 0.004;
    search_mindistance[22] := 0.003;
    search_mindistance[23] := 0.002;
    search_mindistance[24] := 0.002;
    search_mindistance[25] := 0.001;
    search_mindistance[26] := 0.001;

    search_maxdistance[14] := 1;
    search_maxdistance[15] := 0.5;
    search_maxdistance[16] := 0.15;
    search_maxdistance[17] := 0.05;
    search_maxdistance[18] := 0.02;
    search_maxdistance[19] := 0.02;
    search_maxdistance[20] := 0.02;
    search_maxdistance[21] := 0.02;
    search_maxdistance[22] := 0.02;
    search_maxdistance[23] := 0.02;
    search_maxdistance[24] := 0.02;
    search_maxdistance[25] := 0.02;
    search_maxdistance[26] := 0.02;

    -- Speed up searches - just use the centroid of the feature
    -- cheaper but less acurate
    place_centroid := ST_Centroid(NEW.geometry);
    place_geometry_text := 'ST_GeomFromText('''||ST_AsText(NEW.geometry)||''','||ST_SRID(NEW.geometry)||')';

    -- copy the building number to the name
    -- done here rather than on insert to avoid initial indexing
    -- TODO: This might be a silly thing to do
    --IF (NEW.name IS NULL OR array_upper(NEW.name,1) IS NULL) AND NEW.housenumber IS NOT NULL THEN
    --  NEW.name := ARRAY[ROW('ref',NEW.housenumber)::keyvalue];
    --END IF;

    --Temp hack to prevent need to re-index
    IF NEW.name::text = '{"(ref,'||NEW.housenumber||')"}' THEN
      NEW.name := NULL;
    END IF;

    --IF (NEW.name IS NULL OR array_upper(NEW.name,1) IS NULL) AND NEW.type IS NOT NULL THEN
    --  NEW.name := ARRAY[ROW('type',NEW.type)::keyvalue];
    --END IF;

    -- Initialise the name and address vectors using our name
    name_vector := make_keywords(NEW.name);
    nameaddress_vector := name_vector;

    -- some tag combinations add a special id for search
    tagpairid := get_tagpair(NEW.class,NEW.type);
    IF tagpairid IS NOT NULL THEN
      name_vector := name_vector + tagpairid;
    END IF;

--RAISE WARNING '% %', NEW.place_id, NEW.rank_search;

    -- For low level elements we inherit from our parent road
    IF (NEW.rank_search > 27 OR (NEW.type = 'postcode' AND NEW.rank_search = 25)) THEN

--RAISE WARNING 'finding street for %', NEW;

      NEW.street_place_id := null;

      -- to do that we have to find our parent road
      -- Copy data from linked items (points on ways, addr:street links, relations)
      -- Note that addr:street links can only be indexed once the street itself is indexed
      IF NEW.street_place_id IS NULL AND NEW.osm_type = 'N' THEN

        -- Is this node part of a relation?
        FOR relation IN select * from planet_osm_rels where parts @> ARRAY[NEW.osm_id::integer] and members @> ARRAY['n'||NEW.osm_id]
        LOOP
          -- At the moment we only process one type of relation - associatedStreet
          IF relation.tags @> ARRAY['associatedStreet'] AND array_upper(relation.members, 1) IS NOT NULL THEN
            FOR i IN 1..array_upper(relation.members, 1) BY 2 LOOP
              IF NEW.street_place_id IS NULL AND relation.members[i+1] = 'street' THEN
--RAISE WARNING 'node in relation %',relation;
                SELECT place_id from placex where osm_type='W' and osm_id = substring(relation.members[i],2,200)::integer 
                  and rank_search = 26 INTO NEW.street_place_id;
              END IF;
            END LOOP;
          END IF;
        END LOOP;      

--RAISE WARNING 'x1';
        -- Is this node part of a way?
        -- Limit 10 is to work round problem in query plan optimiser
        FOR location IN select * from placex where osm_type = 'W' 
          and osm_id in (select id from planet_osm_ways where nodes && ARRAY[NEW.osm_id::integer] limit 10)
        LOOP
--RAISE WARNING '%', location;
          -- Way IS a road then we are on it - that must be our road
          IF location.rank_search = 26 AND NEW.street_place_id IS NULL THEN
--RAISE WARNING 'node in way that is a street %',location;
            NEW.street_place_id := location.place_id;
          END IF;

          -- Is the WAY part of a relation
          FOR relation IN select * from planet_osm_rels where parts @> ARRAY[location.osm_id::integer] and members @> ARRAY['w'||location.osm_id]
          LOOP
            -- At the moment we only process one type of relation - associatedStreet
            IF relation.tags @> ARRAY['associatedStreet'] AND array_upper(relation.members, 1) IS NOT NULL THEN
              FOR i IN 1..array_upper(relation.members, 1) BY 2 LOOP
                IF NEW.street_place_id IS NULL AND relation.members[i+1] = 'street' THEN
--RAISE WARNING 'node in way that is in a relation %',relation;
                  SELECT place_id from placex where osm_type='W' and osm_id = substring(relation.members[i],2,200)::integer 
                    and rank_search = 26 INTO NEW.street_place_id;
                END IF;
              END LOOP;
            END IF;
          END LOOP;
          
          -- If the way contains an explicit name of a street copy it
          IF NEW.street IS NULL AND location.street IS NOT NULL THEN
--RAISE WARNING 'node in way that has a streetname %',location;
            NEW.street := location.street;
          END IF;

          -- If this way is a street interpolation line then it is probably as good as we are going to get
          IF NEW.street_place_id IS NULL AND NEW.street IS NULL AND location.class = 'place' and location.type='houses' THEN
            -- Try and find a way that is close roughly parellel to this line
            FOR relation IN SELECT place_id FROM placex
              WHERE ST_DWithin(location.geometry, placex.geometry, 0.001) and placex.rank_search = 26
              ORDER BY (ST_distance(placex.geometry, ST_Line_Interpolate_Point(location.geometry,0))+
                        ST_distance(placex.geometry, ST_Line_Interpolate_Point(location.geometry,0.5))+
                        ST_distance(placex.geometry, ST_Line_Interpolate_Point(location.geometry,1))) ASC limit 1
            LOOP
--RAISE WARNING 'using nearest street to address interpolation line,0.001 %',relation;
              NEW.street_place_id := relation.place_id;
            END LOOP;
          END IF;

        END LOOP;
                
      END IF;

--RAISE WARNING 'x2';

      IF NEW.street_place_id IS NULL AND NEW.osm_type = 'W' THEN
        -- Is this way part of a relation?
        FOR relation IN select * from planet_osm_rels where parts @> ARRAY[NEW.osm_id::integer] and members @> ARRAY['w'||NEW.osm_id]
        LOOP
          -- At the moment we only process one type of relation - associatedStreet
          IF relation.tags @> ARRAY['associatedStreet'] AND array_upper(relation.members, 1) IS NOT NULL THEN
            FOR i IN 1..array_upper(relation.members, 1) BY 2 LOOP
              IF NEW.street_place_id IS NULL AND relation.members[i+1] = 'street' THEN
--RAISE WARNING 'way that is in a relation %',relation;
                SELECT place_id from placex where osm_type='W' and osm_id = substring(relation.members[i],2,200)::integer
                  and rank_search = 26 INTO NEW.street_place_id;
              END IF;
            END LOOP;
          END IF;
        END LOOP;
      END IF;
      
--RAISE WARNING 'x3';

      IF NEW.street_place_id IS NULL AND NEW.street IS NOT NULL THEN
      	address_street_word_id := get_name_id(make_standard_name(NEW.street));
        IF address_street_word_id IS NOT NULL THEN
          FOR location IN SELECT place_id,ST_distance(NEW.geometry, search_name.centroid) as distance 
            FROM search_name WHERE search_name.name_vector @> ARRAY[address_street_word_id]
            AND ST_DWithin(NEW.geometry, search_name.centroid, 0.01) and search_rank = 26 
            ORDER BY ST_distance(NEW.geometry, search_name.centroid) ASC limit 1
          LOOP
--RAISE WARNING 'streetname found nearby %',location;
            NEW.street_place_id := location.place_id;
          END LOOP;
        END IF;
        -- Failed, fall back to nearest - don't just stop
        IF NEW.street_place_id IS NULL THEN
--RAISE WARNING 'unable to find streetname nearby % %',NEW.street,address_street_word_id;
--          RETURN null;
        END IF;
      END IF;

--RAISE WARNING 'x4';

      search_diameter := 0.00005;
      WHILE NEW.street_place_id IS NULL AND search_diameter < 0.1 LOOP
--RAISE WARNING '% %', search_diameter,ST_AsText(ST_Centroid(NEW.geometry));
        FOR location IN SELECT place_id FROM placex
          WHERE ST_DWithin(place_centroid, placex.geometry, search_diameter) and rank_search = 26
          ORDER BY ST_distance(NEW.geometry, placex.geometry) ASC limit 1
        LOOP
--RAISE WARNING 'using nearest street,% % %',search_diameter,NEW.street,location;
          NEW.street_place_id := location.place_id;
        END LOOP;
        search_diameter := search_diameter * 2;
      END LOOP;

--RAISE WARNING 'x6 %',NEW.street_place_id;

      -- If we didn't find any road give up, should be VERY rare
      IF NEW.street_place_id IS NOT NULL THEN

        -- Some unnamed roads won't have been indexed, index now if needed
        select count(*) from place_addressline where place_id = NEW.street_place_id INTO street_place_id_count;
        IF street_place_id_count = 0 THEN
          UPDATE placex set indexed = true where indexed = false and place_id = NEW.street_place_id;
        END IF;

        -- Add the street to the address as zero distance to force to front of list
        INSERT INTO place_addressline VALUES (NEW.place_id, NEW.street_place_id, true, true, 0, 26);
        address_havelevel[26] := true;

        -- Import address details from parent, reclculating distance in process
        INSERT INTO place_addressline select NEW.place_id, x.address_place_id, x.fromarea, x.isaddress, ST_distance(NEW.geometry, placex.geometry), placex.rank_address
          from place_addressline as x join placex on (address_place_id = placex.place_id)
          where x.place_id = NEW.street_place_id and x.address_place_id != NEW.street_place_id;

        -- Get the details of the parent road
        select * from search_name where place_id = NEW.street_place_id INTO location;
        NEW.country_code := location.country_code;

--RAISE WARNING '%', NEW.name;
        -- If there is no name it isn't searchable, don't bother to create a search record
        IF NEW.name is NULL THEN
          return NEW;
        END IF;

        -- Merge address from parent
        nameaddress_vector := array_merge(nameaddress_vector, location.nameaddress_vector);

        -- Performance, it would be more acurate to do all the rest of the import process but it takes too long
        -- Just be happy with inheriting from parent road only
        INSERT INTO search_name values (NEW.place_id, NEW.rank_search, NEW.rank_address, NEW.country_code,
          name_vector, nameaddress_vector, place_centroid);

        return NEW;
      END IF;

    END IF;

--RAISE WARNING '  INDEXING: %',NEW;

    -- Process area matches (tend to be better quality)
    FOR location IN SELECT
      place_id,
      name,
      keywords,
      country_code,
      rank_address,
      rank_search,
      ST_Distance(place_centroid, centroid) as distance
      FROM location_area
      WHERE ST_Contains(area, place_centroid) and location_area.rank_search < search_maxrank
      ORDER BY ST_Distance(place_centroid, centroid) ASC
    LOOP

--RAISE WARNING '  AREA: % % %',location.keywords,NEW.country_code,location.country_code;

      IF NEW.country_code IS NULL THEN
        NEW.country_code := location.country_code;
      ELSEIF NEW.country_code != location.country_code and location.rank_search > 3 THEN
        search_country_code_conflict := true;
      END IF;

      -- Add it to the list of search terms
      nameaddress_vector := array_merge(nameaddress_vector, location.keywords::integer[]);
      INSERT INTO place_addressline VALUES (NEW.place_id, location.place_id, true, NOT address_havelevel[location.rank_address], location.distance, location.rank_address); 
      address_havelevel[location.rank_address] := true;

    END LOOP;

    -- try using the isin value to find parent places
    address_maxrank := search_maxrank;
    IF NEW.isin IS NOT NULL THEN
      -- Doing isin without a country code seems to be dangerous
      IF NEW.country_code is null THEN
        NEW.country_code := get_country_code(place_centroid);
      END IF;
      isin := regexp_split_to_array(NEW.isin, E'[;,]');
      FOR i IN 1..array_upper(isin, 1) LOOP
        address_street_word_id := get_name_id(make_standard_name(isin[i]));
        IF address_street_word_id IS NOT NULL THEN
--RAISE WARNING '  search: %',address_street_word_id;
          FOR location IN SELECT place_id,keywords,rank_search,location_point.country_code,rank_address,
            ST_Distance(place_centroid, search_name.centroid) as distance
            FROM search_name join location_point using (place_id)
            WHERE search_name.name_vector @> ARRAY[address_street_word_id]
            AND rank_search < NEW.rank_search
            AND (NEW.country_code IS NULL OR search_name.country_code = NEW.country_code OR search_name.address_rank < 4)
            ORDER BY ST_distance(NEW.geometry, search_name.centroid) ASC limit 1
          LOOP

            IF NEW.country_code IS NULL THEN
              NEW.country_code := location.country_code;
            ELSEIF NEW.country_code != location.country_code and location.rank_search > 3 THEN
              search_country_code_conflict := true;
            END IF;

--RAISE WARNING '  found: %',location.place_id;
            nameaddress_vector := array_merge(nameaddress_vector, location.keywords::integer[]);
            INSERT INTO place_addressline VALUES (NEW.place_id, location.place_id, false, NOT address_havelevel[location.rank_address], location.distance, location.rank_address);

            IF address_maxrank > location.rank_address THEN
              address_maxrank := location.rank_address;
            END IF;
          END LOOP;
        END IF;
      END LOOP;
      FOR i IN address_maxrank..28 LOOP
        address_havelevel[i] := true;
      END LOOP;
    END IF;

    -- If we have got a consistent country code from the areas and/or isin then we don't care about points (too inacurate)
    bPointCountryCode := NEW.country_code IS NULL;

    IF true THEN
    -- full search using absolute position

    search_diameter := 0;
    -- 16 = city, anything larger tends to be an area so don't continue
    WHILE search_diameter < 1 AND search_maxrank > 16 LOOP

--      RAISE WARNING 'Nearest: % %', search_diameter, search_maxrank;

      search_prevdiameter := search_diameter;
      IF search_diameter = 0 THEN
        search_diameter := 0.001;
      ELSE
        search_diameter := search_diameter * 2;
      END IF;

--RAISE WARNING '%', 'SELECT place_id, name, keywords, country_code, rank_address, rank_search,'||
--        'ST_Distance('||place_geometry_text||', centroid) as distance,'||
--        'ST_Distance('||place_geometry_text||', centroid) as maxdistance'|| -- this version of postgis doesnt have maxdistance !
--        ' FROM location_point_'||(case when search_maxrank > 26 THEN 26 ELSE search_maxrank end)||
--        ' WHERE ST_DWithin('||place_geometry_text||', centroid, '||search_diameter||') '||
--        '  AND ST_Distance('||place_geometry_text||', centroid) > '||search_prevdiameter||
--        ' ORDER BY ST_Distance('||place_geometry_text||', centroid) ASC';

      -- Try nearest
      FOR location IN EXECUTE 'SELECT place_id, name, keywords, country_code, rank_address, rank_search,'||
        'ST_Distance('||place_geometry_text||', centroid) as distance,'||
        'ST_Distance('||place_geometry_text||', centroid) as maxdistance'|| -- this version of postgis doesnt have maxdistance !
        ' FROM location_point_'||(case when search_maxrank > 26 THEN 26 ELSE search_maxrank end)||
        ' WHERE ST_DWithin('||place_geometry_text||', centroid, '||search_diameter||') '||
        '  AND ST_Distance('||place_geometry_text||', centroid) >= '||search_prevdiameter||
        ' ORDER BY ST_Distance('||place_geometry_text||', centroid) ASC'
      LOOP

        IF bPointCountryCode THEN      
          IF NEW.country_code IS NULL THEN
            NEW.country_code := location.country_code;
          ELSEIF NEW.country_code != location.country_code THEN
            search_country_code_conflict := true;
          END IF;
        END IF;
    
        -- Find search words
--RAISE WARNING 'IF % % % %', location.name, location.distance, location.rank_search, search_maxdistance;
--RAISE WARNING '  POINT: % % % % %', location.name, location.rank_search, location.place_id, location.distance, search_maxdistance[location.rank_search];
        IF (location.distance < search_maxdistance[location.rank_search]) THEN
--RAISE WARNING '  adding';     
          -- Add it to the list of search terms, de-duplicate
          nameaddress_vector := array_merge(nameaddress_vector, location.keywords::integer[]);
    
          iMax := (location.maxdistance*1.5)::float;
          FOR i IN location.rank_search..28 LOOP
            IF iMax < search_maxdistance[i] THEN
--RAISE WARNING '  setting % to %',i,iMax;     
              IF iMax > search_mindistance[i] THEN
                search_maxdistance[i] := iMax;
              ELSE
                search_maxdistance[i] := search_mindistance[i];
              END IF;
            END IF;
          END LOOP;

          INSERT INTO place_addressline VALUES (NEW.place_id, location.place_id, false, NOT address_havelevel[location.rank_address], location.distance, location.rank_address); 
          address_havelevel[location.rank_address] := true;
  
        ELSE
--RAISE WARNING '  Stopped: % % % %', location.rank_search, location.distance, search_maxdistance[location.rank_search], location.name;
          IF search_maxrank > location.rank_search THEN
            search_maxrank := location.rank_search;
          END IF;
        END IF;
    
      END LOOP;
  
--RAISE WARNING '  POINT LOCATIONS, % %', search_maxrank, search_diameter;
  
    END LOOP; --WHILE

    ELSE
      -- Cascading search using nearest parent
    END IF;

    IF search_country_code_conflict OR NEW.country_code IS NULL THEN
      NEW.country_code := get_country_code(place_centroid);
    END IF;

    INSERT INTO search_name values (NEW.place_id, NEW.rank_search, NEW.rank_search, NEW.country_code, 
      name_vector, nameaddress_vector, place_centroid);

    IF NEW.country_code IS NOT NULL THEN
      DELETE FROM place_addressline WHERE place_id = NEW.place_id and address_place_id in (
        select address_place_id from place_addressline join placex on (address_place_id = placex.place_id)
          where place_addressline.place_id = NEW.place_id and placex.country_code != NEW.country_code and cached_rank_address >= 4);
    END IF;

  END IF;

  return NEW;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION placex_delete() RETURNS TRIGGER
  AS $$
DECLARE
BEGIN

--IF OLD.rank_search < 26 THEN
--RAISE WARNING 'delete % % % % %',OLD.place_id,OLD.osm_type,OLD.osm_id,OLD.class,OLD.type;
--END IF;

  -- mark everything linked to this place for re-indexing
  UPDATE placex set indexed = false from place_addressline where address_place_id = OLD.place_id and placex.place_id = place_addressline.place_id and indexed;

  -- do the actual delete
  DELETE FROM location_area where place_id = OLD.place_id;
  DELETE FROM location_point where place_id = OLD.place_id;
  DELETE FROM location_point_0 where place_id = OLD.place_id;
  DELETE FROM location_point_1 where place_id = OLD.place_id;
  DELETE FROM location_point_2 where place_id = OLD.place_id;
  DELETE FROM location_point_3 where place_id = OLD.place_id;
  DELETE FROM location_point_4 where place_id = OLD.place_id;
  DELETE FROM location_point_5 where place_id = OLD.place_id;
  DELETE FROM location_point_6 where place_id = OLD.place_id;
  DELETE FROM location_point_7 where place_id = OLD.place_id;
  DELETE FROM location_point_8 where place_id = OLD.place_id;
  DELETE FROM location_point_9 where place_id = OLD.place_id;
  DELETE FROM location_point_10 where place_id = OLD.place_id;
  DELETE FROM location_point_11 where place_id = OLD.place_id;
  DELETE FROM location_point_12 where place_id = OLD.place_id;
  DELETE FROM location_point_13 where place_id = OLD.place_id;
  DELETE FROM location_point_14 where place_id = OLD.place_id;
  DELETE FROM location_point_15 where place_id = OLD.place_id;
  DELETE FROM location_point_16 where place_id = OLD.place_id;
  DELETE FROM location_point_17 where place_id = OLD.place_id;
  DELETE FROM location_point_18 where place_id = OLD.place_id;
  DELETE FROM location_point_19 where place_id = OLD.place_id;
  DELETE FROM location_point_20 where place_id = OLD.place_id;
  DELETE FROM location_point_21 where place_id = OLD.place_id;
  DELETE FROM location_point_22 where place_id = OLD.place_id;
  DELETE FROM location_point_23 where place_id = OLD.place_id;
  DELETE FROM location_point_24 where place_id = OLD.place_id;
  DELETE FROM location_point_25 where place_id = OLD.place_id;
  DELETE FROM location_point_26 where place_id = OLD.place_id;
  DELETE FROM search_name where place_id = OLD.place_id;
  DELETE FROM place_addressline where place_id = OLD.place_id;
  DELETE FROM place_addressline where address_place_id = OLD.place_id;

  RETURN OLD;

END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION place_delete() RETURNS TRIGGER
  AS $$
DECLARE
  placeid INTEGER;
BEGIN

--  RAISE WARNING 'delete: % % % %',OLD.osm_type,OLD.osm_id,OLD.class,OLD.type;
  delete from placex where osm_type = OLD.osm_type and osm_id = OLD.osm_id and class = OLD.class;
  RETURN OLD;

END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION place_insert() RETURNS TRIGGER
  AS $$
DECLARE
  i INTEGER;
  existing RECORD;
  existingplacex RECORD;
  existinggeometry GEOMETRY;
  existingplace_id bigint;
  result BOOLEAN;
BEGIN

  IF FALSE AND NEW.osm_type = 'R' THEN
    RAISE WARNING '-----------------------------------------------------------------------------------';
    RAISE WARNING 'place_insert: % % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type,st_area(NEW.geometry);
  END IF;

  -- Just block these - lots and pointless
  IF NEW.class = 'highway' and NEW.type in ('turning_circle','traffic_signals','mini_roundabout','noexit','crossing') THEN
    RETURN null;
  END IF;
  IF NEW.class in ('landuse','natural') and NEW.name is null THEN
    RETURN null;
  END IF;

  IF ST_IsEmpty(NEW.geometry) OR NOT ST_IsValid(NEW.geometry) OR ST_X(ST_Centroid(NEW.geometry))::text in ('NaN','Infinity','-Infinity') OR ST_Y(ST_Centroid(NEW.geometry))::text in ('NaN','Infinity','-Infinity') THEN  
--    RAISE WARNING 'Invalid Geometry: % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type;
    RETURN null;
  END IF;

  -- Patch in additional country names
  -- adminitrative (with typo) is unfortunately hard codes - this probably won't get fixed until v2
  IF NEW.admin_level = 2 AND NEW.type = 'adminitrative' AND NEW.country_code is not null THEN
    select add_keywords(NEW.name, country_name.name) from country_name where country_name.country_code = lower(NEW.country_code) INTO NEW.name;
  END IF;
    
  -- Have we already done this place?
  select * from place where osm_type = NEW.osm_type and osm_id = NEW.osm_id and class = NEW.class and type = NEW.type INTO existing;

  -- Get the existing place_id
  select * from placex where osm_type = NEW.osm_type and osm_id = NEW.osm_id and class = NEW.class and type = NEW.type into existingplacex;

  -- Handle a place changing type by removing the old data
  -- My generated 'place' types are causing havok because they overlap with real tags
  -- TODO: move them to their own special purpose tag to avoid collisions
  IF existing.osm_type IS NULL AND (NEW.type not in ('postcode','house','houses')) THEN
    DELETE FROM place where osm_type = NEW.osm_type and osm_id = NEW.osm_id and class = NEW.class and type not in ('postcode','house','houses');
  END IF;

--  RAISE WARNING 'Existing: %',existing.place_id;

  -- To paraphrase, if there isn't an existing item, OR if the admin level has changed, OR if it is a major change in geometry
  IF existing.osm_type IS NULL 
     OR existingplacex.osm_type IS NULL
     OR coalesce(existing.admin_level, 100) != coalesce(NEW.admin_level, 100) 
--     OR coalesce(existing.country_code, '') != coalesce(NEW.country_code, '')
     OR (existing.geometry != NEW.geometry AND ST_Distance(ST_Centroid(existing.geometry),ST_Centroid(NEW.geometry)) > 0.01 AND NOT
     (ST_GeometryType(existing.geometry) in ('ST_Polygon','ST_MultiPolygon') AND ST_GeometryType(NEW.geometry) in ('ST_Polygon','ST_MultiPolygon')))
     THEN

--    RAISE WARNING 'delete and replace';

    IF existing.osm_type IS NOT NULL THEN
--      RAISE WARNING 'insert delete % % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type,ST_Distance(ST_Centroid(existing.geometry),ST_Centroid(NEW.geometry)),existing;
      IF existing.rank_search < 26 THEN
        RAISE WARNING 'replace placex % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type;
      END IF;
      DELETE FROM place where osm_type = NEW.osm_type and osm_id = NEW.osm_id and class = NEW.class and type = NEW.type;
    END IF;   

    -- No - process it as a new insertion (hopefully of low rank or it will be slow)
    insert into placex values (NEW.place_id
        ,NEW.osm_type
        ,NEW.osm_id
        ,NEW.class
        ,NEW.type
        ,NEW.name
        ,NEW.admin_level
        ,NEW.housenumber
        ,NEW.street
        ,NEW.isin
        ,NEW.postcode
        ,NEW.country_code
        ,NEW.street_place_id
        ,NEW.rank_address
        ,NEW.rank_search
        ,NEW.indexed
        ,NEW.geometry
        );

--    RAISE WARNING 'insert done % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type;

    RETURN NEW;
  END IF;

  -- Various ways to do the update

  -- Debug, what's changed?
  IF FALSE AND existing.rank_search < 26 THEN
    IF coalesce(existing.name::text, '') != coalesce(NEW.name::text, '') THEN
      RAISE WARNING 'update details, name: % % % %',NEW.osm_type,NEW.osm_id,existing.name::text,NEW.name::text;
    END IF;
    IF coalesce(existing.housenumber, '') != coalesce(NEW.housenumber, '') THEN
      RAISE WARNING 'update details, housenumber: % % % %',NEW.osm_type,NEW.osm_id,existing.housenumber,NEW.housenumber;
    END IF;
    IF coalesce(existing.street, '') != coalesce(NEW.street, '') THEN
      RAISE WARNING 'update details, street: % % % %',NEW.osm_type,NEW.osm_id,existing.street,NEW.street;
    END IF;
    IF coalesce(existing.isin, '') != coalesce(NEW.isin, '') THEN
      RAISE WARNING 'update details, isin: % % % %',NEW.osm_type,NEW.osm_id,existing.isin,NEW.isin;
    END IF;
    IF coalesce(existing.postcode, '') != coalesce(NEW.postcode, '') THEN
      RAISE WARNING 'update details, postcode: % % % %',NEW.osm_type,NEW.osm_id,existing.postcode,NEW.postcode;
    END IF;
    IF coalesce(existing.country_code, '') != coalesce(NEW.country_code, '') THEN
      RAISE WARNING 'update details, country_code: % % % %',NEW.osm_type,NEW.osm_id,existing.country_code,NEW.country_code;
    END IF;
  END IF;

  -- Special case for polygon shape changes because they tend to be large and we can be a bit clever about how we handle them
  IF existing.geometry != NEW.geometry 
     AND ST_GeometryType(existing.geometry) in ('ST_Polygon','ST_MultiPolygon')
     AND ST_GeometryType(NEW.geometry) in ('ST_Polygon','ST_MultiPolygon') 
     THEN 

    IF existing.rank_search < 26 THEN
      RAISE WARNING 'existing polygon change % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type;
    END IF;

    -- Get the version of the geometry actually used (in placex table)
    select geometry from placex where osm_type = NEW.osm_type and osm_id = NEW.osm_id and class = NEW.class and type = NEW.type into existinggeometry;

    -- Performance limit
    IF st_area(NEW.geometry) < 1 AND st_area(existinggeometry) < 1 THEN

      -- re-index points that have moved in / out of the polygon, could be done as a single query but postgres gets the index usage wrong
      update placex set indexed = false where indexed and 
          (ST_Contains(NEW.geometry, placex.geometry) OR ST_Intersects(NEW.geometry, placex.geometry))
          AND NOT (ST_Contains(existinggeometry, placex.geometry) OR ST_Intersects(existinggeometry, placex.geometry))
          AND rank_search > NEW.rank_search;

      update placex set indexed = false where indexed and 
          (ST_Contains(existinggeometry, placex.geometry) OR ST_Intersects(existinggeometry, placex.geometry))
          AND NOT (ST_Contains(NEW.geometry, placex.geometry) OR ST_Intersects(NEW.geometry, placex.geometry))
          AND rank_search > NEW.rank_search;

    END IF;

  END IF;

  -- Special case - if we are just adding extra words we hack them into the search_name table rather than reindexing
  IF existingplacex.rank_search < 26
     AND coalesce(existing.housenumber, '') = coalesce(NEW.housenumber, '')
     AND coalesce(existing.street, '') = coalesce(NEW.street, '')
     AND coalesce(existing.isin, '') = coalesce(NEW.isin, '')
     AND coalesce(existing.postcode, '') = coalesce(NEW.postcode, '')
     AND coalesce(existing.country_code, '') = coalesce(NEW.country_code, '')
     AND coalesce(existing.name::text, '') != coalesce(NEW.name::text, '') 
     THEN

    IF existing.rank_search < 26 THEN
      RAISE WARNING 'name change only % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type;
    END IF;

    IF NOT update_location_nameonly(existingplacex.place_id, NEW.name) THEN

      IF st_area(NEW.geometry) < 0.5 THEN
        UPDATE placex set indexed = false from place_addressline where address_place_id = existingplacex.place_id 
          and placex.place_id = place_addressline.place_id and indexed;
      END IF;

    END IF;
  
  ELSE

    -- Anything else has changed - reindex the lot
    IF coalesce(existing.name::text, '') != coalesce(NEW.name::text, '')
        OR coalesce(existing.housenumber, '') != coalesce(NEW.housenumber, '')
        OR coalesce(existing.street, '') != coalesce(NEW.street, '')
        OR coalesce(existing.isin, '') != coalesce(NEW.isin, '')
        OR coalesce(existing.postcode, '') != coalesce(NEW.postcode, '')
        OR coalesce(existing.country_code, '') != coalesce(NEW.country_code, '') THEN

      IF existing.rank_search < 26 THEN
        RAISE WARNING 'other change % % % %',NEW.osm_type,NEW.osm_id,NEW.class,NEW.type;
      END IF;

      -- performance, can't take the load of re-indexing a whole country / huge area
      IF st_area(NEW.geometry) < 0.5 THEN
        UPDATE placex set indexed = false from place_addressline where address_place_id = existingplacex.place_id 
          and placex.place_id = place_addressline.place_id and indexed;
      END IF;

    END IF;

  END IF;

  IF coalesce(existing.name::text, '') != coalesce(NEW.name::text, '')
     OR coalesce(existing.housenumber, '') != coalesce(NEW.housenumber, '')
     OR coalesce(existing.street, '') != coalesce(NEW.street, '')
     OR coalesce(existing.isin, '') != coalesce(NEW.isin, '')
     OR coalesce(existing.postcode, '') != coalesce(NEW.postcode, '')
     OR coalesce(existing.country_code, '') != coalesce(NEW.country_code, '')
     OR existing.geometry != NEW.geometry
     THEN

    update place set 
      name = NEW.name,
      housenumber  = NEW.housenumber,
      street = NEW.street,
      isin = NEW.isin,
      postcode = NEW.postcode,
      country_code = NEW.country_code,
      street_place_id = null,
      geometry = NEW.geometry
      where osm_type = NEW.osm_type and osm_id = NEW.osm_id and class = NEW.class and type = NEW.type;

    update placex set 
      name = NEW.name,
      housenumber = NEW.housenumber,
      street = NEW.street,
      isin = NEW.isin,
      postcode = NEW.postcode,
      country_code = NEW.country_code,
      street_place_id = null,
      indexed = false,
      geometry = NEW.geometry
      where place_id = existingplacex.place_id;

    result := update_location(existingplacex.place_id, existingplacex.country_code, NEW.name, existingplacex.rank_search, existingplacex.rank_address, NEW.geometry);

  END IF;

  -- Abort the add (we modified the existing place instead)
  RETURN NULL;

END; 
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_name_by_language(name keyvalue[], languagepref TEXT[]) RETURNS TEXT
  AS $$
DECLARE
  search TEXT[];
  found BOOLEAN;
BEGIN

  IF (array_upper(name, 1) is null) THEN
    return null;
  END IF;

  search := languagepref;

  FOR j IN 1..array_upper(search, 1) LOOP
    FOR k IN 1..array_upper(name, 1) LOOP
      IF (name[k].key = search[j] AND trim(name[k].value) != '') THEN
        return trim(name[k].value);
      END IF;
    END LOOP;
  END LOOP;

  RETURN null;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION get_connected_ways(way_ids INTEGER[]) RETURNS SETOF planet_osm_ways
  AS $$
DECLARE
  searchnodes INTEGER[];
  location RECORD;
  j INTEGER;
BEGIN

  searchnodes := '{}';
  FOR j IN 1..array_upper(way_ids, 1) LOOP
    FOR location IN 
      select nodes from planet_osm_ways where id = way_ids[j] LIMIT 1
    LOOP
      searchnodes := searchnodes | location.nodes;
    END LOOP;
  END LOOP;

  RETURN QUERY select * from planet_osm_ways where nodes && searchnodes and NOT ARRAY[id] <@ way_ids;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION get_address_postcode(for_place_id BIGINT) RETURNS TEXT
  AS $$
DECLARE
  result TEXT[];
  search TEXT[];
  for_postcode TEXT;
  found INTEGER;
  location RECORD;
BEGIN

  found := 1000;
  search := ARRAY['ref'];
  result := '{}';

  UPDATE placex set indexed = true where indexed = false and place_id = for_place_id;

  select postcode from placex where place_id = for_place_id limit 1 into for_postcode;

  FOR location IN 
    select rank_address,name,distance,length(name::text) as namelength 
      from place_addressline join placex on (address_place_id = placex.place_id) 
      where place_addressline.place_id = for_place_id and rank_address in (5,11)
      order by rank_address desc,rank_search desc,fromarea desc,distance asc,namelength desc
  LOOP
    IF array_upper(search, 1) IS NOT NULL AND array_upper(location.name, 1) IS NOT NULL THEN
      FOR j IN 1..array_upper(search, 1) LOOP
        FOR k IN 1..array_upper(location.name, 1) LOOP
          IF (found > location.rank_address AND location.name[k].key = search[j] AND location.name[k].value != '') AND NOT result && ARRAY[trim(location.name[k].value)] AND (for_postcode IS NULL OR location.name[k].value ilike for_postcode||'%') THEN
            result[(100 - location.rank_address)] := trim(location.name[k].value);
            found := location.rank_address;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END LOOP;

  RETURN array_to_string(result,', ');
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_address_by_language(for_place_id BIGINT, languagepref TEXT[]) RETURNS TEXT
  AS $$
DECLARE
  result TEXT[];
  search TEXT[];
  found INTEGER;
  location RECORD;
  searchcountrycode varchar(2);
  searchhousenumber TEXT;
  searchrankaddress INTEGER;
BEGIN

  found := 1000;
  search := languagepref;
  result := '{}';

--  UPDATE placex set indexed = false where indexed = true and place_id = for_place_id;
  UPDATE placex set indexed = true where indexed = false and place_id = for_place_id;

  select country_code,housenumber,rank_address from placex where place_id = for_place_id into searchcountrycode,searchhousenumber,searchrankaddress;

  FOR location IN 
    select CASE WHEN address_place_id = for_place_id AND rank_address = 0 THEN 100 ELSE rank_address END as rank_address,
      CASE WHEN type = 'postcode' THEN ARRAY[ROW('name',postcode)::keyvalue] ELSE name END as name,
      distance,length(name::text) as namelength 
      from place_addressline join placex on (address_place_id = placex.place_id) 
      where place_addressline.place_id = for_place_id and ((rank_address > 0 AND rank_address < searchrankaddress) OR address_place_id = for_place_id)
      and (placex.country_code IS NULL OR searchcountrycode IS NULL OR placex.country_code = searchcountrycode OR rank_address < 4)
      order by rank_address desc,fromarea desc,distance asc,rank_search desc,namelength desc
  LOOP
    IF array_upper(search, 1) IS NOT NULL AND array_upper(location.name, 1) IS NOT NULL THEN
      FOR j IN 1..array_upper(search, 1) LOOP
        FOR k IN 1..array_upper(location.name, 1) LOOP
          IF (found > location.rank_address AND location.name[k].key = search[j] AND location.name[k].value != '') AND NOT result && ARRAY[trim(location.name[k].value)] THEN
            result[(100 - location.rank_address)] := trim(location.name[k].value);
            found := location.rank_address;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END LOOP;

  IF searchhousenumber IS NOT NULL AND COALESCE(result[(100 - 28)],'') != searchhousenumber THEN
    IF result[(100 - 28)] IS NOT NULL THEN
      result[(100 - 29)] := result[(100 - 28)];
    END IF;
    result[(100 - 28)] := searchhousenumber;
  END IF;

  -- No country polygon - add it from the country_code
  IF found > 4 THEN
    select get_name_by_language(country_name.name,languagepref) as name from placex join country_name using (country_code) 
      where place_id = for_place_id limit 1 INTO location;
    IF location IS NOT NULL THEN
      result[(100 - 4)] := trim(location.name);
    END IF;
  END IF;

  RETURN array_to_string(result,', ');
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_addressdata_by_language(for_place_id BIGINT, languagepref TEXT[]) RETURNS TEXT[]
  AS $$
DECLARE
  result TEXT[];
  search TEXT[];
  found INTEGER;
  location RECORD;
  searchcountrycode varchar(2);
  searchhousenumber TEXT;
BEGIN

  found := 1000;
  search := languagepref;
  result := '{}';

--  UPDATE placex set indexed = false where indexed = true and place_id = for_place_id;
  UPDATE placex set indexed = true where indexed = false and place_id = for_place_id;

  select country_code,housenumber from placex where place_id = for_place_id into searchcountrycode,searchhousenumber;

  FOR location IN 
    select CASE WHEN address_place_id = for_place_id AND rank_address = 0 THEN 100 ELSE rank_address END as rank_address,
      name,distance,length(name::text) as namelength 
      from place_addressline join placex on (address_place_id = placex.place_id) 
      where place_addressline.place_id = for_place_id and (rank_address > 0 OR address_place_id = for_place_id)
      and (placex.country_code IS NULL OR searchcountrycode IS NULL OR placex.country_code = searchcountrycode OR rank_address < 4)
      order by rank_address desc,fromarea desc,distance asc,rank_search desc,namelength desc
  LOOP
    IF array_upper(search, 1) IS NOT NULL AND array_upper(location.name, 1) IS NOT NULL THEN
      FOR j IN 1..array_upper(search, 1) LOOP
        FOR k IN 1..array_upper(location.name, 1) LOOP
          IF (found > location.rank_address AND location.name[k].key = search[j] AND location.name[k].value != '') AND NOT result && ARRAY[trim(location.name[k].value)] THEN
            result[(100 - location.rank_address)] := trim(location.name[k].value);
            found := location.rank_address;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END LOOP;

  IF searchhousenumber IS NOT NULL AND result[(100 - 28)] IS NULL THEN
    result[(100 - 28)] := searchhousenumber;
  END IF;

  -- No country polygon - add it from the country_code
  IF found > 4 THEN
    select get_name_by_language(country_name.name,languagepref) as name from placex join country_name using (country_code) 
      where place_id = for_place_id limit 1 INTO location;
    IF location IS NOT NULL THEN
      result[(100 - 4)] := trim(location.name);
    END IF;
  END IF;

  RETURN result;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_place_boundingbox(search_place_id INTEGER) RETURNS place_boundingbox
  AS $$
DECLARE
  result place_boundingbox;
  numfeatures integer;
BEGIN
  select * from place_boundingbox into result where place_id = search_place_id;
  IF result.place_id IS NULL THEN
-- remove  isaddress = true because if there is a matching polygon it always wins
    select count(*) from place_addressline where address_place_id = search_place_id into numfeatures;
    insert into place_boundingbox select place_id,
             ST_Y(ST_PointN(ExteriorRing(ST_Box2D(area)),4)),ST_Y(ST_PointN(ExteriorRing(ST_Box2D(area)),2)),
             ST_X(ST_PointN(ExteriorRing(ST_Box2D(area)),1)),ST_X(ST_PointN(ExteriorRing(ST_Box2D(area)),3)),
             numfeatures, ST_Area(area),
             area from location_area where place_id = search_place_id;
    select * from place_boundingbox into result where place_id = search_place_id;
  END IF;
  IF result.place_id IS NULL THEN
-- TODO 0.0001
    insert into place_boundingbox select address_place_id,
             min(ST_Y(ST_Centroid(geometry))) as minlon,max(ST_Y(ST_Centroid(geometry))) as maxlon,
             min(ST_X(ST_Centroid(geometry))) as minlat,max(ST_X(ST_Centroid(geometry))) as maxlat,
             count(*), ST_Area(ST_Buffer(ST_Convexhull(ST_Collect(geometry)),0.0001)) as area,
             ST_Buffer(ST_Convexhull(ST_Collect(geometry)),0.0001) as boundary 
             from (select * from place_addressline where address_place_id = search_place_id order by cached_rank_address limit 4000) as place_addressline join placex using (place_id) 
             where address_place_id = search_place_id
--               and (isaddress = true OR place_id = search_place_id)
               and (st_length(geometry) < 0.01 or place_id = search_place_id)
             group by address_place_id limit 1;
    select * from place_boundingbox into result where place_id = search_place_id;
  END IF;
  return result;
END;
$$
LANGUAGE plpgsql;

-- don't do the operation if it would be slow
CREATE OR REPLACE FUNCTION get_place_boundingbox_quick(search_place_id INTEGER) RETURNS place_boundingbox
  AS $$
DECLARE
  result place_boundingbox;
  numfeatures integer;
  rank integer;
BEGIN
  select * from place_boundingbox into result where place_id = search_place_id;
  IF result IS NULL AND rank > 14 THEN
    select count(*) from place_addressline where address_place_id = search_place_id and isaddress = true into numfeatures;
    insert into place_boundingbox select place_id,
             ST_Y(ST_PointN(ExteriorRing(ST_Box2D(area)),4)),ST_Y(ST_PointN(ExteriorRing(ST_Box2D(area)),2)),
             ST_X(ST_PointN(ExteriorRing(ST_Box2D(area)),1)),ST_X(ST_PointN(ExteriorRing(ST_Box2D(area)),3)),
             numfeatures, ST_Area(area),
             area from location_area where place_id = search_place_id;
    select * from place_boundingbox into result where place_id = search_place_id;
  END IF;
  IF result IS NULL THEN
    select rank_search from placex where place_id = search_place_id into rank;
    IF rank > 20 THEN
-- TODO 0.0001
      insert into place_boundingbox select address_place_id,
             min(ST_Y(ST_Centroid(geometry))) as minlon,max(ST_Y(ST_Centroid(geometry))) as maxlon,
             min(ST_X(ST_Centroid(geometry))) as minlat,max(ST_X(ST_Centroid(geometry))) as maxlat,
             count(*), ST_Area(ST_Buffer(ST_Convexhull(ST_Collect(geometry)),0.0001)) as area,
             ST_Buffer(ST_Convexhull(ST_Collect(geometry)),0.0001) as boundary 
             from place_addressline join placex using (place_id) 
             where address_place_id = search_place_id 
               and (isaddress = true OR place_id = search_place_id)
               and (st_length(geometry) < 0.01 or place_id = search_place_id)
             group by address_place_id limit 1;
      select * from place_boundingbox into result where place_id = search_place_id;
    END IF;
  END IF;
  return result;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_place(search_place_id INTEGER) RETURNS BOOLEAN
  AS $$
DECLARE
  result place_boundingbox;
  numfeatures integer;
BEGIN
  update placex set 
      name = place.name,
      housenumber = place.housenumber,
      street = place.street,
      isin = place.isin,
      postcode = place.postcode,
      country_code = place.country_code,
      street_place_id = null,
      indexed = false      
      from place
      where placex.place_id = search_place_id 
        and place.osm_type = placex.osm_type and place.osm_id = placex.osm_id
        and place.class = placex.class and place.type = placex.type;
  update placex set indexed = true where place_id = search_place_id and indexed = false;
  return true;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_searchrank_label(rank INTEGER) RETURNS TEXT
  AS $$
DECLARE
BEGIN
  IF rank < 2 THEN
    RETURN 'Continent';
  ELSEIF rank < 4 THEN
    RETURN 'Sea';
  ELSEIF rank < 8 THEN
    RETURN 'Country';
  ELSEIF rank < 12 THEN
    RETURN 'State';
  ELSEIF rank < 16 THEN
    RETURN 'County';
  ELSEIF rank = 16 THEN
    RETURN 'City';
  ELSEIF rank = 17 THEN
    RETURN 'Town / Island';
  ELSEIF rank = 18 THEN
    RETURN 'Village / Hamlet';
  ELSEIF rank = 20 THEN
    RETURN 'Suburb';
  ELSEIF rank = 21 THEN
    RETURN 'Postcode Area';
  ELSEIF rank = 22 THEN
    RETURN 'Croft / Farm / Locality / Islet';
  ELSEIF rank = 23 THEN
    RETURN 'Postcode Area';
  ELSEIF rank = 25 THEN
    RETURN 'Postcode Point';
  ELSEIF rank = 26 THEN
    RETURN 'Street / Major Landmark';
  ELSEIF rank = 27 THEN
    RETURN 'Minory Street / Path';
  ELSEIF rank = 28 THEN
    RETURN 'House / Building';
  ELSE
    RETURN 'Other: '||rank;
  END IF;
  
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_addressrank_label(rank INTEGER) RETURNS TEXT
  AS $$
DECLARE
BEGIN
  IF rank = 0 THEN
    RETURN 'None';
  ELSEIF rank < 2 THEN
    RETURN 'Continent';
  ELSEIF rank < 4 THEN
    RETURN 'Sea';
  ELSEIF rank = 5 THEN
    RETURN 'Postcode';
  ELSEIF rank < 8 THEN
    RETURN 'Country';
  ELSEIF rank < 12 THEN
    RETURN 'State';
  ELSEIF rank < 16 THEN
    RETURN 'County';
  ELSEIF rank = 16 THEN
    RETURN 'City';
  ELSEIF rank = 17 THEN
    RETURN 'Town / Village / Hamlet';
  ELSEIF rank = 20 THEN
    RETURN 'Suburb';
  ELSEIF rank = 21 THEN
    RETURN 'Postcode Area';
  ELSEIF rank = 22 THEN
    RETURN 'Croft / Farm / Locality / Islet';
  ELSEIF rank = 23 THEN
    RETURN 'Postcode Area';
  ELSEIF rank = 25 THEN
    RETURN 'Postcode Point';
  ELSEIF rank = 26 THEN
    RETURN 'Street / Major Landmark';
  ELSEIF rank = 27 THEN
    RETURN 'Minory Street / Path';
  ELSEIF rank = 28 THEN
    RETURN 'House / Building';
  ELSE
    RETURN 'Other: '||rank;
  END IF;
  
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_word_suggestion(srcword TEXT) RETURNS TEXT
  AS $$
DECLARE
  trigramtoken TEXT;
  result TEXT;
BEGIN

  trigramtoken := regexp_replace(make_standard_name(srcword),E'([^0-9])\\1+',E'\\1','g');
  SELECT word FROM word WHERE word_trigram like ' %' and word_trigram % trigramtoken ORDER BY similarity(word_trigram, trigramtoken) DESC, word limit 1 into result;

  return result;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_word_suggestions(srcword TEXT) RETURNS TEXT[]
  AS $$
DECLARE
  trigramtoken TEXT;
  result TEXT[];
  r RECORD;
BEGIN

  trigramtoken := regexp_replace(make_standard_name(srcword),E'([^0-9])\\1+',E'\\1','g');

  FOR r IN SELECT word,similarity(word_trigram, trigramtoken) as score FROM word 
    WHERE word_trigram like ' %' and word_trigram % trigramtoken ORDER BY similarity(word_trigram, trigramtoken) DESC, word limit 4
  LOOP
    result[coalesce(array_upper(result,1)+1,1)] := r.word;
  END LOOP;

  return result;
END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_word_letterfequency(srcword TEXT) RETURNS INTEGER[]
  AS $$
DECLARE
  letterfeq INTEGER[];
  i INTEGER;
BEGIN
  letterfeq[97] := 0;
  letterfeq[101] := 0;
  letterfeq[105] := 0;
  letterfeq[114] := 0;
  letterfeq[116] := 0;
  letterfeq[115] := 0;
  letterfeq[111] := 0;
  letterfeq[117] := 0;
  letterfeq[110] := 0;
  letterfeq[100] := 0;
  FOR i IN 1..length(srcword) LOOP
    i := ascii(substring(srcword, i, 1));
    IF (i = 97 OR i = 101 OR i = 105 OR i = 114 OR i = 116 OR i = 115 OR i = 111 OR i = 117 OR i = 110 OR i = 100) AND letterfeq[i] < 7 THEN
      letterfeq[i] := letterfeq[i] + 1;
    END IF;
  END LOOP;
  RETURN letterfeq;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_word_indexval(a INTEGER,e INTEGER,i INTEGER,r INTEGER,t INTEGER,s INTEGER,o INTEGER,u INTEGER,n INTEGER,d INTEGER) RETURNS INTEGER
  AS $$
DECLARE
BEGIN
  RETURN (a << 0) + (e << 3) + (i << 6) + (r << 9) + (t << 12) + (s << 15) + (o << 18) + (u << 21) + (n << 24) + (d << 27);
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_word_indexkey(srcword TEXT) RETURNS INTEGER
  AS $$
DECLARE
  letterfeq INTEGER[];
BEGIN

  letterfeq := get_word_letterfequency(srcword);
  RETURN get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);

END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_word_indexnear(srcword TEXT) RETURNS INTEGER[]
  AS $$
DECLARE
  letterfeq INTEGER[];
  near INTEGER[];
BEGIN


  letterfeq := get_word_letterfequency(srcword);

  near := ARRAY[get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100])];

  IF letterfeq[97] > 0 THEN
    near := near || get_word_indexval(letterfeq[97]-1, letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;
  IF letterfeq[97] < 7 THEN
    near := near || get_word_indexval(letterfeq[97]+1, letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;

  IF letterfeq[101] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101]-1, letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;
  IF letterfeq[101] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101]+1, letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;

  IF letterfeq[105] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105]-1, letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;
  IF letterfeq[105] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105]+1, letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;

  IF letterfeq[114] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114]-1, letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;
  IF letterfeq[114] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114]+1, letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;

  IF letterfeq[116] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116]-1, letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;
  IF letterfeq[116] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116]+1, letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;

  IF letterfeq[115] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115]-1, letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;
  IF letterfeq[115] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115]+1, letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;

  IF letterfeq[111] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111]-1, letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;
  IF letterfeq[111] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111]+1, letterfeq[117], letterfeq[110], letterfeq[100]);
  END IF;

  IF letterfeq[117] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117]-1, letterfeq[110], letterfeq[100]);
  END IF;
  IF letterfeq[117] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117]+1, letterfeq[110], letterfeq[100]);
  END IF;

  IF letterfeq[110] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110]-1, letterfeq[100]);
  END IF;
  IF letterfeq[110] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110]+1, letterfeq[100]);
  END IF;

  IF letterfeq[100] > 0 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]-1);
  END IF;
  IF letterfeq[100] < 7 THEN
    near := near || get_word_indexval(letterfeq[97], letterfeq[101], letterfeq[105], letterfeq[114], letterfeq[116], letterfeq[115], letterfeq[111], letterfeq[117], letterfeq[110], letterfeq[100]+1);
  END IF;

  RETURN near;  
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_trigram_ids(lookup_word TEXT)
  RETURNS INTEGER[]
  AS $$
DECLARE
  gram1 INTEGER;
  gram2 INTEGER;
  gram3 INTEGER;

  gram INTEGER[];
  gramsorted INTEGER[];
  trigramgram INTEGER[];
BEGIN

  trigramgram := '{}'::int[];
  gram := '{1,1,1}'::int[];

  FOR i in 1..length(lookup_word) LOOP
    gram[1] := gram[2];
    gram[2] := gram[3];
    gram[3] := ascii(substring(lookup_word,i,1));
    gramsorted := sort(gram);
    trigramgram := trigramgram + (gramsorted[1] + gramsorted[2]*128 + gramsorted[3]*16384);
  END LOOP;

  gram[1] := gram[2];
  gram[2] := gram[3];
  gram[3] := 1;
  gramsorted := sort(gram);
  trigramgram := trigramgram + (gramsorted[1] + gramsorted[2]*128 + gramsorted[3]*16384);

  gram[1] := gram[2];
  gram[2] := gram[3];
  gram[3] := 1;
  gramsorted := sort(gram);
  trigramgram := trigramgram + (gramsorted[1] + gramsorted[2]*128 + gramsorted[3]*16384);

  RETURN uniq(sort(trigramgram));
END;
$$
LANGUAGE plpgsql;

