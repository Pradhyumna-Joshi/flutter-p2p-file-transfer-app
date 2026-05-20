package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

var connections = make(map[string]*websocket.Conn, 0)
var mu sync.RWMutex

type Message struct {
	From string `json:"from"`
	To   string `json:"to"`
	Type string `json:"type"`
	Data string `json:"data"`
}

func main() {

	mux := http.NewServeMux()

	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println("Error", err)
			return
		}

		log.Println(conn.RemoteAddr())

		for {
			_, msg, err := conn.ReadMessage()
			if err != nil {
				log.Println("Error", err)
				return
			}

			log.Printf("Recieved : %s", msg)

			var message Message

			if err := json.Unmarshal(msg, &message); err != nil {
				log.Println("Error", err)
				return
			}

			if strings.ToLower(message.Type) == "register" {
				mu.Lock()
				connections[message.From] = conn
				fmt.Println("Conn", connections)
				mu.Unlock()
			} else {
				fmt.Println("Conn", connections)
				mu.RLock()
				targetConn, ok := connections[message.To]
				if !ok {
					message.Type = "error"
					message.Data = "No such user exists!!"
					targetConn = connections[message.From]
				}
				str, err := json.Marshal(message)
				if err != nil {
					log.Println("Error", err)
					return
				}
				if err := targetConn.WriteMessage(websocket.TextMessage, str); err != nil {
					log.Println("Error", err)
					return
				}

				mu.RUnlock()

			}
		}

	})

	log.Println("Server running on port : 8080")
	http.ListenAndServe(":8080", mux)

}
