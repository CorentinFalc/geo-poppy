---------------------------------
--Synchronisation des données entre Geopoppy et un serveur central
--Julien ANCELIN
--Diffusé sous licence open-source AGPL
---------------------------------

--exemple: select sync.rpi2server('nom_connexion','ip','host','port','user','password','database');

DROP FUNCTION IF EXISTS sync.rpi2server();
CREATE OR REPLACE FUNCTION sync.rpi2server(n text, h text, p integer, u text, pw text, db text, OUT count_data_in int, OUT count_data_out int) AS $$
DECLARE
query text;
ii int;
BEGIN
	--connect dblink remote server and verify if same connection alive
	IF dblink_get_connections() is NULL
	THEN
		PERFORM dblink_connect(''||n||'','host='||h||' port='||p||' user='||u||' password='||pw||' dbname='||db||'') ;
		raise NOTICE 'connection: %',''||n||'';
	ELSE
		PERFORM dblink_disconnect(''||n||'');
		PERFORM dblink_connect(''||n||'','host='||h||' port='||p||' user='||u||' password='||pw||' dbname='||db||'');
		raise NOTICE 'connection: %',''||n||'';
	END IF;
	--get number of rows to sync
	SELECT count(ts) from sauv_data WHERE sauv_data.sync = 0 INTO count_data_in;
	RAISE NOTICE 'count_data_in : %', count_data_in;
	--get data and execute INSERT INTO in remote server
	--update sync column in sauv_data to 1 (penser à rajouter le schema sync)
	FOR query IN
		SELECT 'SELECT dblink_exec('''||n||''',''INSERT INTO sync.sauv_data values 
		('''''||n||''''','''''||ts||''''','''''||schema_bd||''''','''''||tbl||''''','''''||action1||''''','''''||sauv||''''','''''|| pk ||''''')'');
		UPDATE sauv_data SET sync = 1, sync_ts = now() WHERE ts = '''||ts||''';'
		FROM sauv_data
		WHERE sauv_data.sync = 0
	LOOP
		EXECUTE query;
		RAISE NOTICE 'ACTION:  %',query;	--messages logs
	END LOOP;
	--get number of rows sync
	GET DIAGNOSTICS ii = ROW_COUNT;
	SELECT ii INTO count_data_out;
	RAISE NOTICE 'count_data_out : %', count_data_out;
	--disconnect dblink remote server
	PERFORM dblink_disconnect(''||n||'');
	raise NOTICE 'déconnection: %',''||n||'';
END;
$$ LANGUAGE plpgsql VOLATILE;
--COST 100 
--ROWS 1000;
ALTER FUNCTION sync.rpi2server(text, text, integer, text, text, text)
  OWNER TO docker;

-----------------------------------------------------
-----------------------------------------------------
---create sync_table synchro
CREATE TABLE sync.synchro
(
  id serial,
  ts timestamp with time zone, --TIME OF SYNCHRO
  id_login integer --get dblink remote server param
);

--FUNCTION synchronis: lors de l'ajout d'une ligne (choix de la connexion dblink), la synchronistaion des données se lance vers le central,
-- Un ts est intégré ensuite dans la table synchro pour pister la synchro
DROP FUNCTION IF EXISTS sync.synchronis() CASCADE;
CREATE OR REPLACE FUNCTION sync.synchronis() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT') THEN
		PERFORM sync.rpi2server(l.nom , l.ip,l.port,l.utilisateur,l.mdp,l.dbname)
		FROM (SELECT * FROM sync.login where id = NEW.id_login ) as l; 
		UPDATE sync.synchro SET id = NEW.id, ts = now(), id_login =NEW.id_login, rpi2server= 'OK'  where id = NEW.id; 
		RETURN NEW;
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER FUNCTION sync.synchronis()
  OWNER TO docker;


--INSERT INTO sync.synchro (id_login) values ( 3);



