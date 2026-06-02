package list_ex

import li "core:container/intrusive/list"

insertAfter :: proc "contextless" (list: ^li.List, currentNode: ^li.Node, newNode: ^li.Node) {
	newNode.prev = currentNode
	newNode.next = currentNode.next

	if currentNode.next != nil {
		currentNode.next.prev = newNode
	} else {
		list.tail = newNode
	}
	currentNode.next = newNode
}

insertBefore :: proc "contextless" (list: ^li.List, currentNode: ^li.Node, newNode: ^li.Node) {
	newNode.next = currentNode
	newNode.prev = currentNode.prev

	if currentNode.prev != nil {
		currentNode.prev.next = newNode
	} else {
		list.head = newNode
	}
	currentNode.prev = newNode
}
