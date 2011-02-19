
DROP TABLE public.auction_data;
DROP TABLE public.auction_accounts;

--
-- Name: auction_accounts; Type: TABLE; Schema: public; Owner: ledq; Tablespace: 
--

CREATE TABLE auction_accounts (
    id integer NOT NULL,
    platform integer DEFAULT 0 NOT NULL,
    username text,
    auth_token text,
    hard_expiration_time text
);


ALTER TABLE public.auction_accounts OWNER TO ledq;

--
-- Name: auction_data; Type: TABLE; Schema: public; Owner: ledq; Tablespace: 
--

CREATE TABLE auction_data (
    id integer DEFAULT nextval(('id'::text)::regclass) NOT NULL,
    account_id integer,
    auction_id text,
    title text,
    description text,
    bidder_id text,
    itime timestamp without time zone DEFAULT now() NOT NULL,
    sell_price numeric(15,5) DEFAULT 0.00 NOT NULL,
    transport_price numeric(15,5) DEFAULT 0.00 NOT NULL,
    status text
);


CREATE UNIQUE INDEX table_id ON auction_accounts USING btree (id);
CREATE UNIQUE INDEX table_id ON auction_data USING btree (id);
