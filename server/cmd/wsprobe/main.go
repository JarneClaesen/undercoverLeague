// Command wsprobe is a throwaway client for poking the server by hand:
//
//	go run ./cmd/wsprobe -url ws://localhost:8080/ws -create -lobby t1 -name Alice
//	go run ./cmd/wsprobe -url ws://localhost:8080/ws -lobby t1 -name Bob
//
// It prints every event it receives and forwards each line typed on stdin
// as a raw JSON command, e.g. {"type":"start"} or {"type":"vote","votedFor":"Bob"}.
package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/coder/websocket"
)

func main() {
	url := flag.String("url", "ws://localhost:8080/ws", "WebSocket URL")
	lobby := flag.String("lobby", "", "lobby ID")
	name := flag.String("name", "", "player name")
	create := flag.Bool("create", false, "create the lobby instead of joining it")
	flag.Parse()

	ctx := context.Background()
	c, _, err := websocket.Dial(ctx, *url, nil)
	if err != nil {
		fmt.Fprintln(os.Stderr, "dial:", err)
		os.Exit(1)
	}
	defer c.CloseNow()

	if *lobby != "" && *name != "" {
		typ := "join"
		if *create {
			typ = "create"
		}
		msg := fmt.Sprintf(`{"type":%q,"reqId":1,"lobbyId":%q,"name":%q}`, typ, *lobby, *name)
		if err := c.Write(ctx, websocket.MessageText, []byte(msg)); err != nil {
			fmt.Fprintln(os.Stderr, "write:", err)
			os.Exit(1)
		}
	}

	go func() {
		for {
			_, data, err := c.Read(ctx)
			if err != nil {
				fmt.Fprintln(os.Stderr, "closed:", err)
				os.Exit(0)
			}
			fmt.Printf("%s <- %s\n", time.Now().Format("15:04:05"), data)
		}
	}()

	in := bufio.NewScanner(os.Stdin)
	for in.Scan() {
		line := in.Text()
		if line == "" {
			continue
		}
		if err := c.Write(ctx, websocket.MessageText, []byte(line)); err != nil {
			fmt.Fprintln(os.Stderr, "write:", err)
			return
		}
	}
	c.Close(websocket.StatusNormalClosure, "bye")
}
