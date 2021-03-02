package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/gorilla/mux"
)

var mapdir string

const defaultCertDir string = "/etc/pki/site/ssl/certs/"

type automountMapEntry struct {
	Name string `json:"name"`
}

type automountEntry struct {
	Name string `json:"name"`
	Map  string `json:"map"`
	Info string `json:"info"`
}

type automount struct {
	AutomountMap []automountMapEntry `json:"automountMap"`
	Automount    []automountEntry    `json:"automount"`
}

type groupEntry struct {
	Name    string   `json:"name"`
	GId     int      `json:"gid"`
	Members []string `json:"members"`
}

type group []groupEntry

type servicesEntry struct {
	Name      string   `json:"name"`
	Port      int      `json:"port"`
	Protocols []string `json:"protocols"`
	Aliases   []string `json:"aliases"`
}

type services []servicesEntry

type userEntry struct {
	Name    string `json:"name"`
	UId     int    `json:"uid"`
	GId     int    `json:"gid"`
	Gecos   string `json:"gecos"`
	Homedir string `json:"homedir"`
	Shell   string `json:"shell"`
}

type user []userEntry

func printHeaders(w http.ResponseWriter, r *http.Request) {
	for name, values := range r.Header {
		for _, value := range values {
			fmt.Fprintf(w, "%s: %s\n", name, value)
		}
	}
}

func doUnmarshall(f string, object interface{}) error {
	filename := mapdir + "/" + f
	file, err := ioutil.ReadFile(filename)
	if err != nil {
		return fmt.Errorf("Could not open %s for reading, %s\n", filename, err)
	}
	if err = json.Unmarshal([]byte(file), &object); err != nil {
		return fmt.Errorf("Could not unmarshall JSON, %s", err)
	}
	return nil
}

func doMarshall(object interface{}) ([]byte, error) {
	anyB, err := json.Marshal(object)
	if err != nil {
		return nil, fmt.Errorf("Could not Marshall JSON, %s", err)
	}
	return anyB, nil
}

func anyHandler(w http.ResponseWriter, r *http.Request) {
	var anyB []byte
	var err error

	vars := mux.Vars(r)
	switch vars["key"] {
	case "automount":
		var a automount
		if err = doUnmarshall("automount.json", &a); err == nil {
			anyB, err = doMarshall(a)
		}
	case "group":
		var g group
		if err = doUnmarshall("groups.json", &g); err == nil {
			anyB, err = doMarshall(g)
		}
	case "services":
		var s services
		if err = doUnmarshall("services.json", &s); err == nil {
			anyB, err = doMarshall(s)
		}
	case "user":
		var u user
		if err = doUnmarshall("users.json", &u); err == nil {
			anyB, err = doMarshall(u)
		}
	}

	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "err\n", err)
		return
	}
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, string(anyB))
}

func main() {
	hostname, err := os.Hostname()
	if err != nil {
		log.Fatalf("%s\n", err)
	}

	defaultCert := defaultCertDir + hostname + ".crt"
	defaultKey := defaultCertDir + hostname + ".key"

	port := flag.Int("port", 8080, "HTTPS Port")
	cert := flag.String("cert", defaultCert, "TLS Cert")
	key := flag.String("key", defaultKey, "TLS Key")
	flag.StringVar(&mapdir, "mapdir", "", "JSON map files directory")
	flag.Parse()

	if mapdir == "" {
		log.Fatal("mapdir is a required argument\n")
	}

	r := mux.NewRouter()
	r.StrictSlash(true)
	r.HandleFunc("/{key}", anyHandler)
	log.Fatal(http.ListenAndServeTLS(":"+strconv.Itoa(*port), *cert, *key, r))
}
